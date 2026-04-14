// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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
    address internal relayer;

    function setUp() public {
        stablecoin = new MockStablecoin();
        serverSigner = vm.addr(SERVER_PK);
        relayer = makeAddr("relayer");

        claims =
            new PayoutClaims(address(stablecoin), serverSigner, CHECK_IN_AMOUNT, MAX_DAILY_CHECK_INS, address(this));

        stablecoin.mint(address(claims), INITIAL_FUNDING);
    }

    function test_DailyCheckIn_First100UsersCanClaim() public {
        uint256 day = claims.currentDay();

        for (uint256 i = 0; i < MAX_DAILY_CHECK_INS; i++) {
            address user = address(uint160(i + 1));
            uint256 nonce = 0;
            uint256 deadline = block.timestamp + 1 hours;
            bytes memory signature = _signCheckIn(user, day, nonce, deadline);

            vm.prank(relayer);
            claims.claimDailyCheckIn(user, day, nonce, deadline, signature);

            assertEq(stablecoin.balanceOf(user), CHECK_IN_AMOUNT);
        }

        assertEq(claims.dailyCheckInCount(day), MAX_DAILY_CHECK_INS);
        assertEq(stablecoin.balanceOf(address(claims)), INITIAL_FUNDING - (MAX_DAILY_CHECK_INS * CHECK_IN_AMOUNT));

        address user101 = address(uint160(101));
        uint256 nonce101 = 0;
        uint256 deadline101 = block.timestamp + 1 hours;
        bytes memory signature101 = _signCheckIn(user101, day, nonce101, deadline101);

        vm.expectRevert(PayoutClaims.DailyLimitReached.selector);
        vm.prank(relayer);
        claims.claimDailyCheckIn(user101, day, nonce101, deadline101, signature101);
    }

    function test_DailyCheckIn_CannotClaimTwiceSameDay() public {
        address user = makeAddr("alice");
        uint256 day = claims.currentDay();

        bytes memory signature1 = _signCheckIn(user, day, 0, block.timestamp + 1 hours);

        vm.prank(relayer);
        claims.claimDailyCheckIn(user, day, 0, block.timestamp + 1 hours, signature1);

        bytes memory signature2 = _signCheckIn(user, day, 2, block.timestamp + 1 hours);

        vm.expectRevert(PayoutClaims.AlreadyClaimedToday.selector);
        vm.prank(relayer);
        claims.claimDailyCheckIn(user, day, 2, block.timestamp + 1 hours, signature2);
    }

    function test_DailyCheckIn_RequiresAuthorizedSigner() public {
        address user = makeAddr("bob");
        uint256 day = claims.currentDay();
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 wrongSignerPk = 0xBEEF;
        bytes memory badSignature = _signCheckInWithPk(wrongSignerPk, user, day, nonce, deadline);

        vm.expectRevert(PayoutClaims.InvalidSigner.selector);
        vm.prank(relayer);
        claims.claimDailyCheckIn(user, day, nonce, deadline, badSignature);
    }

    function test_DailyCheckIn_RevertsOnExpiredSignature() public {
        address user = makeAddr("carol");
        uint256 day = claims.currentDay();
        uint256 nonce = 0;
        uint256 deadline = block.timestamp - 1;

        bytes memory signature = _signCheckIn(user, day, nonce, deadline);

        vm.expectRevert(PayoutClaims.SignatureExpired.selector);
        vm.prank(relayer);
        claims.claimDailyCheckIn(user, day, nonce, deadline, signature);
    }

    function test_LeaderboardClaim_SuccessAndClaimIdSingleUse() public {
        address user = makeAddr("winner");
        uint256 amount = 25e18;
        bytes32 claimId = keccak256("leaderboard-epoch-1-place-1");
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory signature = _signLeaderboard(user, amount, claimId, 0, deadline);

        vm.prank(relayer);
        claims.claimLeaderboardPayout(user, amount, claimId, 0, deadline, signature);

        assertEq(stablecoin.balanceOf(user), amount);

        bytes memory anotherSignature = _signLeaderboard(user, amount, claimId, 1, deadline);
        vm.expectRevert(PayoutClaims.LeaderboardClaimAlreadyUsed.selector);
        vm.prank(relayer);
        claims.claimLeaderboardPayout(user, amount, claimId, 1, deadline, anotherSignature);
    }

    function test_SignerCompromise_DrainsTreasuryAndBlocksLegitimateClaims() public {
        address attacker = makeAddr("attacker");
        uint256 deadline = block.timestamp + 1 hours;
        uint256 treasuryBalance = stablecoin.balanceOf(address(claims));

        bytes32 attackerClaimId = keccak256("compromised-signer-drain");
        bytes memory attackerSignature = _signLeaderboard(attacker, treasuryBalance, attackerClaimId, 0, deadline);

        vm.prank(relayer);
        claims.claimLeaderboardPayout(attacker, treasuryBalance, attackerClaimId, 0, deadline, attackerSignature);

        assertEq(stablecoin.balanceOf(attacker), treasuryBalance);
        assertEq(stablecoin.balanceOf(address(claims)), 0);

        address honestUser = makeAddr("honest-user");
        uint256 day = claims.currentDay();
        bytes memory honestSignature = _signCheckIn(honestUser, day, 0, deadline);

        vm.expectRevert(PayoutClaims.InsufficientContractBalance.selector);
        vm.prank(relayer);
        claims.claimDailyCheckIn(honestUser, day, 0, deadline, honestSignature);
    }

    function test_LeaderboardClaim_CollisionAcrossUsersBlocksSecondValidClaim() public {
        address userOne = makeAddr("leaderboard-user-one");
        address userTwo = makeAddr("leaderboard-user-two");
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 sharedClaimId = keccak256("shared-claim-id");

        uint256 userOneAmount = 12e18;
        uint256 userTwoAmount = 34e18;

        bytes memory userOneSignature = _signLeaderboard(userOne, userOneAmount, sharedClaimId, 0, deadline);
        bytes memory userTwoSignature = _signLeaderboard(userTwo, userTwoAmount, sharedClaimId, 0, deadline);

        vm.prank(relayer);
        claims.claimLeaderboardPayout(userOne, userOneAmount, sharedClaimId, 0, deadline, userOneSignature);
        assertEq(stablecoin.balanceOf(userOne), userOneAmount);

        vm.expectRevert(PayoutClaims.LeaderboardClaimAlreadyUsed.selector);
        vm.prank(relayer);
        claims.claimLeaderboardPayout(userTwo, userTwoAmount, sharedClaimId, 0, deadline, userTwoSignature);
        assertEq(stablecoin.balanceOf(userTwo), 0);
    }

    function test_DailyCheckIn_RevertsOnInvalidNonce() public {
        address user = makeAddr("nonce-user");
        uint256 day = claims.currentDay();
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = _signCheckIn(user, day, nonce, deadline);

        vm.expectRevert(PayoutClaims.InvalidNonce.selector);
        vm.prank(relayer);
        claims.claimDailyCheckIn(user, day, nonce, deadline, signature);
    }

    function test_NonceDomains_AreIndependentAcrossClaimTypes() public {
        address user = makeAddr("nonce-domain-user");
        uint256 day = claims.currentDay();
        uint256 deadline = block.timestamp + 1 hours;

        uint256 leaderboardAmount = 5e18;
        bytes32 leaderboardClaimId = keccak256("nonce-domain-claim");
        bytes memory leaderboardSignature = _signLeaderboard(user, leaderboardAmount, leaderboardClaimId, 0, deadline);

        vm.prank(relayer);
        claims.claimLeaderboardPayout(user, leaderboardAmount, leaderboardClaimId, 0, deadline, leaderboardSignature);

        assertEq(claims.leaderboardNonces(user), 1);
        assertEq(claims.checkInNonces(user), 0);

        bytes memory checkInSignature = _signCheckIn(user, day, 0, deadline);

        vm.prank(relayer);
        claims.claimDailyCheckIn(user, day, 0, deadline, checkInSignature);

        assertEq(claims.checkInNonces(user), 1);
        assertEq(claims.leaderboardNonces(user), 1);
    }

    function test_OwnerWithdraw_OnlyOwnerCanWithdraw() public {
        address attacker = makeAddr("attacker-withdraw");
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));

        vm.prank(attacker);
        claims.ownerWithdraw(attacker, 1e18);
    }

    function test_OwnerWithdraw_ValidatesRecipientAndBalance() public {
        vm.expectRevert(PayoutClaims.ZeroAddress.selector);
        claims.ownerWithdraw(address(0), 1e18);

        uint256 overdrawAmount = stablecoin.balanceOf(address(claims)) + 1;
        vm.expectRevert(PayoutClaims.InsufficientContractBalance.selector);
        claims.ownerWithdraw(address(this), overdrawAmount);
    }

    function _signCheckIn(address user, uint256 day, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        return _signCheckInWithPk(SERVER_PK, user, day, nonce, deadline);
    }

    function _signCheckInWithPk(uint256 signerPk, address user, uint256 day, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = claims.hashCheckInClaim(user, day, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signLeaderboard(address user, uint256 amount, bytes32 claimId, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = claims.hashLeaderboardClaim(user, amount, claimId, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SERVER_PK, digest);
        return abi.encodePacked(r, s, v);
    }
}
