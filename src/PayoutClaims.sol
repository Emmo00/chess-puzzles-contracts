// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PayoutClaims is Ownable, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    bytes32 public constant CHECK_IN_TYPEHASH =
        keccak256("CheckInClaim(address user,uint256 day,uint256 nonce,uint256 deadline)");
    bytes32 public constant LEADERBOARD_TYPEHASH =
        keccak256("LeaderboardClaim(address user,uint256 amount,bytes32 claimId,uint256 nonce,uint256 deadline)");

    IERC20 public immutable payoutToken;
    address public serverSigner;

    uint256 public checkInAmount;
    uint256 public maxDailyCheckIns;

    mapping(uint256 day => uint256 count) public dailyCheckInCount;
    mapping(uint256 day => mapping(address user => bool hasClaimed)) public hasClaimedDailyCheckIn;
    mapping(bytes32 digest => bool used) public usedDigests;
    mapping(bytes32 claimId => bool used) public usedLeaderboardClaimIds;

    event DailyCheckInClaimed(uint256 indexed day, address indexed user, uint256 amount, uint256 nonce, bytes32 digest);
    event LeaderboardClaimed(
        bytes32 indexed claimId, address indexed user, uint256 amount, uint256 nonce, bytes32 digest
    );
    event ServerSignerUpdated(address indexed previousSigner, address indexed newSigner);
    event CheckInAmountUpdated(uint256 previousAmount, uint256 newAmount);
    event MaxDailyCheckInsUpdated(uint256 previousMax, uint256 newMax);
    event OwnerWithdrawal(address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroValue();
    error InvalidSigner();
    error SignatureExpired();
    error InvalidCheckInDay();
    error AlreadyClaimedToday();
    error DailyLimitReached();
    error DigestAlreadyUsed();
    error LeaderboardClaimAlreadyUsed();
    error InsufficientContractBalance();

    constructor(
        address token,
        address initialServerSigner,
        uint256 initialCheckInAmount,
        uint256 initialMaxDailyCheckIns,
        address initialOwner
    ) Ownable(initialOwner) EIP712("MiniPayPayoutClaims", "1") {
        if (token == address(0) || initialServerSigner == address(0) || initialOwner == address(0)) {
            revert ZeroAddress();
        }
        if (initialCheckInAmount == 0 || initialMaxDailyCheckIns == 0) revert ZeroValue();

        payoutToken = IERC20(token);
        serverSigner = initialServerSigner;
        checkInAmount = initialCheckInAmount;
        maxDailyCheckIns = initialMaxDailyCheckIns;
    }

    function currentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function claimDailyCheckIn(uint256 day, uint256 nonce, uint256 deadline, bytes calldata signature)
        external
        nonReentrant
    {
        if (deadline < block.timestamp) revert SignatureExpired();
        if (day != currentDay()) revert InvalidCheckInDay();
        if (hasClaimedDailyCheckIn[day][msg.sender]) revert AlreadyClaimedToday();
        if (dailyCheckInCount[day] >= maxDailyCheckIns) revert DailyLimitReached();

        bytes32 structHash = keccak256(abi.encode(CHECK_IN_TYPEHASH, msg.sender, day, nonce, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);

        _consumeAuthorizedDigest(digest, signature);

        hasClaimedDailyCheckIn[day][msg.sender] = true;
        unchecked {
            dailyCheckInCount[day] += 1;
        }

        _payout(msg.sender, checkInAmount);
        emit DailyCheckInClaimed(day, msg.sender, checkInAmount, nonce, digest);
    }

    function claimLeaderboardPayout(
        uint256 amount,
        bytes32 claimId,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        if (deadline < block.timestamp) revert SignatureExpired();
        if (usedLeaderboardClaimIds[claimId]) revert LeaderboardClaimAlreadyUsed();

        bytes32 structHash = keccak256(abi.encode(LEADERBOARD_TYPEHASH, msg.sender, amount, claimId, nonce, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);

        _consumeAuthorizedDigest(digest, signature);

        usedLeaderboardClaimIds[claimId] = true;
        _payout(msg.sender, amount);
        emit LeaderboardClaimed(claimId, msg.sender, amount, nonce, digest);
    }

    function setServerSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        emit ServerSignerUpdated(serverSigner, newSigner);
        serverSigner = newSigner;
    }

    function setCheckInAmount(uint256 newAmount) external onlyOwner {
        if (newAmount == 0) revert ZeroValue();
        emit CheckInAmountUpdated(checkInAmount, newAmount);
        checkInAmount = newAmount;
    }

    function setMaxDailyCheckIns(uint256 newMax) external onlyOwner {
        if (newMax == 0) revert ZeroValue();
        emit MaxDailyCheckInsUpdated(maxDailyCheckIns, newMax);
        maxDailyCheckIns = newMax;
    }

    function ownerWithdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        _payout(to, amount);
        emit OwnerWithdrawal(to, amount);
    }

    function hashCheckInClaim(address user, uint256 day, uint256 nonce, uint256 deadline)
        external
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(CHECK_IN_TYPEHASH, user, day, nonce, deadline));
        return _hashTypedDataV4(structHash);
    }

    function hashLeaderboardClaim(address user, uint256 amount, bytes32 claimId, uint256 nonce, uint256 deadline)
        external
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(LEADERBOARD_TYPEHASH, user, amount, claimId, nonce, deadline));
        return _hashTypedDataV4(structHash);
    }

    function _consumeAuthorizedDigest(bytes32 digest, bytes calldata signature) internal {
        if (usedDigests[digest]) revert DigestAlreadyUsed();

        address recovered = ECDSA.recover(digest, signature);
        if (recovered != serverSigner) revert InvalidSigner();

        usedDigests[digest] = true;
    }

    function _payout(address to, uint256 amount) internal {
        if (payoutToken.balanceOf(address(this)) < amount) revert InsufficientContractBalance();
        payoutToken.safeTransfer(to, amount);
    }
}
