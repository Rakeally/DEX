// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./jkToken"

interface IDex {
    function createPool(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    ) external;

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    ) external;

    function removeLiquidity(address tokenA, address tokenB) external;

    function swapToken(address from, address to, uint amount) external;
}

contract Dex is IDex, ReentrancyGuard {
    mapping(bytes => Pool) pools;
    address public owner;
    uint public LP_INITIAL_AMNT;
    uint public LP_FEE;
    JKToken private jkToken;
    IERC20 private dai;
    IERC20 private usdc;

    address private immutable daiAddress =
        0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357;
    address private immutable usdcAddress =
        0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address private immutable JKERC20Token =
        0x0443A3d33dA8b33C94d2B0f10c969A459D1b498C;

    constructor() {
        jkToken = JKToken(JKERC20Token);
        dai = IERC20(daiAddress);
        usdc = IERC20(usdcAddress);
        owner = msg.sender;
        LP_INITIAL_AMNT = 1000 * 1e18;
        LP_FEE = 30; // base percent as uniswap
    }

    struct Pool {
        mapping(address => uint) tokenBalances;
        mapping(address => uint) lpBalance;
        uint totalLpTokens; //Liquidity Pool Tokens
    }

    function createPool(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    )
        external
        hasEnoughAllowance(tokenA, tokenB, amountA, amountB)
        nonReentrant
    {
        require(amountA > 0 && amountB > 0, "amount must be greater than 0");
        Pool storage pool = _getPool(tokenA, tokenB);
        require(pool.tokenBalances[tokenA] == 0, "Pool already exist");

        _transferToken(tokenA, tokenB, amountA, amountB);

        pool.tokenBalances[tokenA] = amountA;
        pool.tokenBalances[tokenB] = amountB;
        bool s = jkToken.transfer(address(this), msg.sender, LP_INITIAL_AMNT);
        require(s, "Transfer failed");
        pool.lpBalance[msg.sender] = LP_INITIAL_AMNT;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    )
        external
        nonReentrant
        hasEnoughAllowance(tokenA, tokenB, amountA, amountB)
    {
        require(tokenA != tokenB, "Tokens must be different");
        require(
            tokenA != address(0) && tokenB != address(0),
            "Tokens address must be valid"
        );

        //check if pool exist
        Pool storage pool = _getPool(tokenA, tokenB);
        uint tokenABalance = pool.tokenBalances[tokenA];
        uint tokenBBalance = pool.tokenBalances[tokenB];

        require(tokenABalance != 0, "Pool doesn't exist");
        require(tokenBBalance != 0, "Pool doesn't exist");

        uint256 tokenAPrice = getSpotPrice(tokenA, tokenB);
        require(
            tokenAPrice * amountA == amountB * 1e18,
            "must add liquidity at the current spot price"
        );

        _transferToken(tokenA, tokenB, amountA, amountB);

        uint newTokens = (amountA * LP_INITIAL_AMNT) / tokenABalance;

        pool.tokenBalances[tokenA] += amountA;
        pool.tokenBalances[tokenB] += amountB;

        //mint new tokens for liquidity provider
        bool s = jkToken.transfer(address(this), msg.sender, newTokens);
        require(s, "Transfer failed");
        pool.totalLpTokens += newTokens;
        pool.lpBalance[msg.sender] += newTokens;
    }

    function removeLiquidity(
        address tokenA,
        address tokenB
    ) external nonReentrant {
        require(tokenA != tokenB, "Tokens must be different");
        require(
            tokenA != address(0) && tokenB != address(0),
            "Tokens address must be valid"
        );

        Pool storage pool = _getPool(tokenA, tokenB);
        uint tokenABalance = pool.tokenBalances[tokenA];
        uint tokenBBalance = pool.tokenBalances[tokenB];
        uint balance = pool.lpBalance[msg.sender];

        require(tokenABalance != 0, "Pool doesn't exist");
        require(tokenBBalance != 0, "Pool doesn't exist");

        require(balance > 0, "no liquidity provided by this user");

        //how much of tokenA and tokenB should we send to the LP
        uint tokenAAmount = (balance * tokenABalance) == 0
            ? 0
            : (balance * tokenABalance) / pool.totalLpTokens;
        uint tokenBAmount = (balance * tokenBBalance) == 0
            ? 0
            : (balance * tokenBBalance) / pool.totalLpTokens;

        pool.lpBalance[msg.sender] = 0;
        pool.tokenBalances[tokenA] -= tokenABalance;
        pool.tokenBalances[tokenB] -= tokenBBalance;
        pool.totalLpTokens -= balance;

        //send tokens to user
        require(
            IERC20(tokenA).transfer(msg.sender, tokenAAmount),
            "transfer failed"
        );
        require(
            IERC20(tokenB).transfer(msg.sender, tokenBAmount),
            "transfer failed"
        );
    }

    function swapToken(address from, address to, uint amount) external {
        require(from != to, "Tokens must be different");
        require(
            from != address(0) && to != address(0),
            "Tokens address must be valid"
        );

        Pool storage pool = _getPool(from, to);
        uint fromBalance = pool.tokenBalances[from];
        uint toBalance = pool.tokenBalances[to];

        require(fromBalance != 0, "Pool doesn't exist");
        require(toBalance != 0, "Pool doesn't exist");

        //deltaY = y * r * deltaX / x + (r * deltaX)
        uint r = 10_000 - LP_FEE;
        uint rDeltaX = (r * amount) / 10_000;

        uint outputTokens = (pool.tokenBalances[to] * rDeltaX) /
            (fromBalance + rDeltaX);

        pool.tokenBalances[from] += amount;
        pool.tokenBalances[to] -= outputTokens;

        require(
            IERC20(from).transferFrom(msg.sender, address(this), amount),
            "transfer failed"
        );
        require(
            IERC20(to).transfer(msg.sender, outputTokens),
            "transfer failed"
        );
    }

    function _getPool(
        address tokenA,
        address tokenB
    ) internal view returns (Pool storage pool) {
        bytes memory key;
        if (tokenA < tokenB) {
            key = abi.encodePacked(tokenA, tokenB);
        } else {
            key = abi.encodePacked(tokenB, tokenA);
        }
        return pools[key];
    }

    function getSpotPrice(
        address tokenA,
        address tokenB
    ) public view returns (uint) {
        Pool storage pool = _getPool(tokenA, tokenB);
        require(
            pool.tokenBalances[tokenA] > 0 && pool.tokenBalances[tokenB] > 0,
            "balance must be non-zero"
        );
        return (pool.tokenBalances[tokenB] * 1e18) / pool.tokenBalances[tokenA];
    }

    function _transferToken(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    ) internal {
        require(
            IERC20(tokenA).transferFrom(msg.sender, address(this), amountA),
            "Transfer failed"
        );
        require(
            IERC20(tokenB).transferFrom(msg.sender, address(this), amountB),
            "Transfer failed"
        );
    }

    modifier hasEnoughAllowance(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    ) {
        require(tokenA != tokenB, "Tokens must be different");
        require(
            tokenA != address(0) && tokenB != address(0),
            "Tokens address must be valid"
        );

        require(
            IERC20(tokenA).balanceOf(msg.sender) >= amountA,
            "Insufficient balance"
        );
        require(
            IERC20(tokenB).balanceOf(msg.sender) >= amountB,
            "Insufficient balance"
        );

        require(
            IERC20(tokenA).allowance(msg.sender, address(this)) >= amountA,
            "Insufficient allowance"
        );
        require(
            IERC20(tokenB).allowance(msg.sender, address(this)) >= amountB,
            "Insufficient allowance"
        );

        _;
    }

    function allowanceUSDC() external view returns (uint256) {
        return usdc.allowance(owner, address(this));
    }

    function allowanceDAI() external view returns (uint256) {
        return dai.allowance(owner, address(this));
    }

    function getContractBalance(
        address _tokenAddress
    ) external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    function getBalance(address _tokenAddress) external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(owner);
    }
}
