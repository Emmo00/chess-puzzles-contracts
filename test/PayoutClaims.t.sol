// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PayoutClaims} from "../src/PayoutClaims.sol";

contract MockStablecoin is ERC20 {
    constructor() ERC20("Mock Stablecoin", "mUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PayoutClaimsTest is Test {
    uint256 internal constant CHECK_IN_AMOUNT = 1e16; // 0.01 with 18 decimals
    uint256 internal constant MAX_DAILY_CHECK_INS = 100;
    uint256 internal constant INITIAL_FUNDING = 1_000_000e18;

    uint256 internal constant SERVER_PK = 0xA11CE;

    MockStablecoin internal stablecoin;
    PayoutClaims internal claims;
    address internal serverSigner;

    function setUp() public {
        stablecoin = new MockStablecoin();
        serverSigner = vm.addr(SERVER_PK);

        claims = new PayoutClaims(
            address(stablecoin),
            serverSigner,
            CHECK_IN_AMOUNT,
            MAX_DAILY_CHECK_INS,
            address(this)
        );

        stablecoin.mint(address(claims), INITIAL_FUNDING);
    }

    function test_DailyCheckIn_First100UsersCanClaim() public {
        uint256 day = claims.currentDay();

        for (uint256 i = 0; i < MAX_DAILY_CHECK_INS; i++) {
            address user = address(uint160(i + 1));
            uint256 nonce = i + 1;
            uint256 deadline = block.timestamp + 1 hours;
            bytes memory signature = _signCheckIn(user, day, nonce, deadline);

            vm.prank(user);
            claims.claimDailyCheckIn(day, nonce, deadline, signature);

            assertEq(stablecoin.balanceOf(user), CHECK_IN_AMOUNT);
        }

        assertEq(claims.dailyCheckInCount(day), MAX_DAILY_CHECK_INS);
        assertEq(stablecoin.balanceOf(address(claims)), INITIAL_FUNDING - (MAX_DAILY_CHECK_INS * CHECK_IN_AMOUNT));

        address user101 = address(uint160(101));
        uint256 nonce101 = 101;
        uint256 deadline101 = block.timestamp + 1 hours;
        bytes memory signature101 = _signCheckIn(user101, day, nonce101, deadline101);

        vm.expectRevert(PayoutClaims.DailyLimitReached.selector);
        vm.prank(user101);
        claims.claimDailyCheckIn(day, nonce101, deadline101, signature101);
    }

    function test_DailyCheckIn_CannotClaimTwiceSameDay() public {
        address user = makeAddr("alice");
        uint256 day = claims.currentDay();

        bytes memory signature1 = _signCheckIn(user, day, 1, block.timestamp + 1 hours);

        vm.prank(user);
        claims.claimDailyCheckIn(day, 1, block.timestamp + 1 hours, signature1);

        bytes memory signature2 = _signCheckIn(user, day, 2, block.timestamp + 1 hours);

        vm.expectRevert(PayoutClaims.AlreadyClaimedToday.selector);
        vm.prank(user);
        claims.claimDailyCheckIn(day, 2, block.timestamp + 1 hours, signature2);
    }

    function test_DailyCheckIn_RequiresAuthorizedSigner() public {
        address user = makeAddr("bob");
        uint256 day = claims.currentDay();
        uint256 nonce = 10;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 wrongSignerPk = 0xBEEF;
        bytes memory badSignature = _signCheckInWithPk(wrongSignerPk, user, day, nonce, deadline);

        vm.expectRevert(PayoutClaims.InvalidSigner.selector);
        vm.prank(user);
        claims.claimDailyCheckIn(day, nonce, deadline, badSignature);
    }

    function test_DailyCheckIn_RevertsOnExpiredSignature() public {
        address user = makeAddr("carol");
        uint256 day = claims.currentDay();
        uint256 nonce = 99;
        uint256 deadline = block.timestamp - 1;

        bytes memory signature = _signCheckIn(user, day, nonce, deadline);

        vm.expectRevert(PayoutClaims.SignatureExpired.selector);
        vm.prank(user);
        claims.claimDailyCheckIn(day, nonce, deadline, signature);
    }

    function test_LeaderboardClaim_SuccessAndClaimIdSingleUse() public {
        address user = makeAddr("winner");
        uint256 amount = 25e18;
        bytes32 claimId = keccak256("leaderboard-epoch-1-place-1");
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory signature = _signLeaderboard(user, amount, claimId, 111, deadline);

        vm.prank(user);
        claims.claimLeaderboardPayout(amount, claimId, 111, deadline, signature);

        assertEq(stablecoin.balanceOf(user), amount);

        bytes memory anotherSignature = _signLeaderboard(user, amount, claimId, 112, deadline);
        vm.expectRevert(PayoutClaims.LeaderboardClaimAlreadyUsed.selector);
        vm.prank(user);
        claims.claimLeaderboardPayout(amount, claimId, 112, deadline, anotherSignature);
    }

    function _signCheckIn(address user, uint256 day, uint256 nonce, uint256 deadline) internal view returns (bytes memory) {
        return _signCheckInWithPk(SERVER_PK, user, day, nonce, deadline);
    }

    function _signCheckInWithPk(
        uint256 signerPk,
        address user,
        uint256 day,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 digest = claims.hashCheckInClaim(user, day, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signLeaderboard(
        address user,
        uint256 amount,
        bytes32 claimId,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 digest = claims.hashLeaderboardClaim(user, amount, claimId, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SERVER_PK, digest);
        return abi.encodePacked(r, s, v);
    }
}