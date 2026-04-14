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

    IERC20 public immutable PAYOUT_TOKEN;
    address public serverSigner;

    uint256 public checkInAmount;
    uint256 public maxDailyCheckIns;

    mapping(uint256 day => uint256 count) public dailyCheckInCount;
    mapping(uint256 day => mapping(address user => bool hasClaimed)) public hasClaimedDailyCheckIn;
    mapping(address user => uint256 nonce) public checkInNonces;
    mapping(address user => uint256 nonce) public leaderboardNonces;
    mapping(bytes32 digest => bool used) public usedDigests;
    mapping(bytes32 claimId => bool used) public usedLeaderboardClaimIds;

    event DailyCheckInClaimed(
        uint256 indexed day,
        address indexed user,
        address indexed relayer,
        uint256 amount,
        uint256 nonce,
        bytes32 digest
    );
    event LeaderboardClaimed(
        bytes32 indexed claimId,
        address indexed user,
        address indexed relayer,
        uint256 amount,
        uint256 nonce,
        bytes32 digest
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
    error InvalidNonce();
    error AlreadyClaimedToday();
    error DailyLimitReached();
    error DigestAlreadyUsed();
    error LeaderboardClaimAlreadyUsed();
    error InsufficientContractBalance();

    /// @notice Deploys the payout claims contract with initial payout configuration.
    /// @param token ERC20 token used for all payouts.
    /// @param initialServerSigner Authorized signer for EIP-712 claim approvals.
    /// @param initialCheckInAmount Payout amount for each successful daily check-in.
    /// @param initialMaxDailyCheckIns Maximum number of daily check-ins allowed per day.
    /// @param initialOwner Address that receives contract ownership.
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

        PAYOUT_TOKEN = IERC20(token);
        serverSigner = initialServerSigner;
        checkInAmount = initialCheckInAmount;
        maxDailyCheckIns = initialMaxDailyCheckIns;
    }

    /// @notice Returns the current day index used for daily check-in accounting.
    /// @dev The day index is based on UTC epoch days: block.timestamp / 1 days.
    /// @return day The current epoch day number.
    function currentDay() public view returns (uint256 day) {
        return block.timestamp / 1 days;
    }

    /// @notice Claims a daily check-in payout for a user using an authorized signature.
    /// @param user Recipient of the payout.
    /// @param day Epoch day included in the signed payload.
    /// @param nonce Expected check-in nonce for the user.
    /// @param deadline Signature expiration timestamp.
    /// @param signature EIP-712 signature produced by serverSigner.
    function claimDailyCheckIn(address user, uint256 day, uint256 nonce, uint256 deadline, bytes calldata signature)
        external
        nonReentrant
    {
        if (user == address(0)) revert ZeroAddress();
        if (deadline < block.timestamp) revert SignatureExpired();
        if (day != currentDay()) revert InvalidCheckInDay();
        if (hasClaimedDailyCheckIn[day][user]) revert AlreadyClaimedToday();
        if (dailyCheckInCount[day] >= maxDailyCheckIns) revert DailyLimitReached();
        if (nonce != checkInNonces[user]) revert InvalidNonce();

        bytes32 structHash = _hashCheckInStruct(user, day, nonce, deadline);
        bytes32 digest = _hashTypedDataV4(structHash);

        _consumeAuthorizedDigest(digest, signature);

        hasClaimedDailyCheckIn[day][user] = true;
        unchecked {
            dailyCheckInCount[day] += 1;
            checkInNonces[user] += 1;
        }

        _payout(user, checkInAmount);
        emit DailyCheckInClaimed(day, user, msg.sender, checkInAmount, nonce, digest);
    }

    /// @notice Claims a leaderboard payout for a user using an authorized signature.
    /// @param user Recipient of the payout.
    /// @param amount Token amount to transfer.
    /// @param claimId Unique leaderboard claim identifier.
    /// @param nonce Expected leaderboard nonce for the user.
    /// @param deadline Signature expiration timestamp.
    /// @param signature EIP-712 signature produced by serverSigner.
    function claimLeaderboardPayout(
        address user,
        uint256 amount,
        bytes32 claimId,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        if (user == address(0)) revert ZeroAddress();
        if (deadline < block.timestamp) revert SignatureExpired();
        if (usedLeaderboardClaimIds[claimId]) revert LeaderboardClaimAlreadyUsed();
        if (nonce != leaderboardNonces[user]) revert InvalidNonce();

        bytes32 structHash = _hashLeaderboardStruct(user, amount, claimId, nonce, deadline);
        bytes32 digest = _hashTypedDataV4(structHash);

        _consumeAuthorizedDigest(digest, signature);

        usedLeaderboardClaimIds[claimId] = true;
        unchecked {
            leaderboardNonces[user] += 1;
        }
        _payout(user, amount);
        emit LeaderboardClaimed(claimId, user, msg.sender, amount, nonce, digest);
    }

    /// @notice Updates the address allowed to sign claim payloads.
    /// @param newSigner New authorized signer address.
    function setServerSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();
        emit ServerSignerUpdated(serverSigner, newSigner);
        serverSigner = newSigner;
    }

    /// @notice Updates the payout amount used for daily check-ins.
    /// @param newAmount New token amount paid per daily check-in.
    function setCheckInAmount(uint256 newAmount) external onlyOwner {
        if (newAmount == 0) revert ZeroValue();
        emit CheckInAmountUpdated(checkInAmount, newAmount);
        checkInAmount = newAmount;
    }

    /// @notice Updates the per-day maximum number of check-in claims.
    /// @param newMax New daily cap for check-in claims.
    function setMaxDailyCheckIns(uint256 newMax) external onlyOwner {
        if (newMax == 0) revert ZeroValue();
        emit MaxDailyCheckInsUpdated(maxDailyCheckIns, newMax);
        maxDailyCheckIns = newMax;
    }

    /// @notice Withdraws payout tokens from the contract to a target address.
    /// @param to Recipient of withdrawn tokens.
    /// @param amount Amount of tokens to withdraw.
    function ownerWithdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        _payout(to, amount);
        emit OwnerWithdrawal(to, amount);
    }

    /// @notice Computes the EIP-712 digest for a daily check-in claim payload.
    /// @param user Recipient encoded in the payload.
    /// @param day Epoch day encoded in the payload.
    /// @param nonce Check-in nonce encoded in the payload.
    /// @param deadline Expiration timestamp encoded in the payload.
    /// @return digest EIP-712 typed data digest.
    function hashCheckInClaim(address user, uint256 day, uint256 nonce, uint256 deadline)
        external
        view
        returns (bytes32 digest)
    {
        bytes32 structHash = _hashCheckInStruct(user, day, nonce, deadline);
        return _hashTypedDataV4(structHash);
    }

    /// @notice Computes the EIP-712 digest for a leaderboard claim payload.
    /// @param user Recipient encoded in the payload.
    /// @param amount Amount encoded in the payload.
    /// @param claimId Claim identifier encoded in the payload.
    /// @param nonce Leaderboard nonce encoded in the payload.
    /// @param deadline Expiration timestamp encoded in the payload.
    /// @return digest EIP-712 typed data digest.
    function hashLeaderboardClaim(address user, uint256 amount, bytes32 claimId, uint256 nonce, uint256 deadline)
        external
        view
        returns (bytes32 digest)
    {
        bytes32 structHash = _hashLeaderboardStruct(user, amount, claimId, nonce, deadline);
        return _hashTypedDataV4(structHash);
    }

    /// @dev Computes the EIP-712 struct hash for a daily check-in claim using inline assembly.
    /// @param user Recipient encoded in the struct.
    /// @param day Epoch day encoded in the struct.
    /// @param nonce Check-in nonce encoded in the struct.
    /// @param deadline Expiration timestamp encoded in the struct.
    /// @return structHash keccak256 hash of the encoded check-in struct.
    function _hashCheckInStruct(address user, uint256 day, uint256 nonce, uint256 deadline)
        internal
        pure
        returns (bytes32 structHash)
    {
        bytes32 typeHash = CHECK_IN_TYPEHASH;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, typeHash)
            mstore(add(ptr, 0x20), and(user, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            mstore(add(ptr, 0x40), day)
            mstore(add(ptr, 0x60), nonce)
            mstore(add(ptr, 0x80), deadline)
            structHash := keccak256(ptr, 0xA0)
        }
    }

    /// @dev Computes the EIP-712 struct hash for a leaderboard claim using inline assembly.
    /// @param user Recipient encoded in the struct.
    /// @param amount Amount encoded in the struct.
    /// @param claimId Claim identifier encoded in the struct.
    /// @param nonce Leaderboard nonce encoded in the struct.
    /// @param deadline Expiration timestamp encoded in the struct.
    /// @return structHash keccak256 hash of the encoded leaderboard struct.
    function _hashLeaderboardStruct(address user, uint256 amount, bytes32 claimId, uint256 nonce, uint256 deadline)
        internal
        pure
        returns (bytes32 structHash)
    {
        bytes32 typeHash = LEADERBOARD_TYPEHASH;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, typeHash)
            mstore(add(ptr, 0x20), and(user, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            mstore(add(ptr, 0x40), amount)
            mstore(add(ptr, 0x60), claimId)
            mstore(add(ptr, 0x80), nonce)
            mstore(add(ptr, 0xA0), deadline)
            structHash := keccak256(ptr, 0xC0)
        }
    }

    /// @dev Validates signer authorization and marks the digest as used to prevent replay.
    /// @param digest EIP-712 digest recovered from the claim payload.
    /// @param signature Signature expected to be produced by serverSigner.
    function _consumeAuthorizedDigest(bytes32 digest, bytes calldata signature) internal {
        if (usedDigests[digest]) revert DigestAlreadyUsed();

        address recovered = ECDSA.recover(digest, signature);
        if (recovered != serverSigner) revert InvalidSigner();

        usedDigests[digest] = true;
    }

    /// @dev Transfers payout tokens after ensuring sufficient contract balance.
    /// @param to Recipient address for token transfer.
    /// @param amount Amount of tokens to transfer.
    function _payout(address to, uint256 amount) internal {
        if (PAYOUT_TOKEN.balanceOf(address(this)) < amount) revert InsufficientContractBalance();
        PAYOUT_TOKEN.safeTransfer(to, amount);
    }
}
