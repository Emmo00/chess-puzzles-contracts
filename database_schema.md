# Project Database Schema Documentation

This project uses **MongoDB** with **Mongoose** as the ODM (Object Data Modeling) library. The schemas are defined in the `lib/models` directory.

## Overview of Models

- [User](#user)
- [DailyChallenge](#dailychallenge)
- [CheckInReservation](#checkinreservation)
- [FarcasterNotificationToken](#farcasternotificationtoken)
- [Payment](#payment)
- [UserPuzzle](#userpuzzle)

---

## User
Stores user profile information, statistics, and settings.

| Field | Type | Description |
| :--- | :--- | :--- |
| `walletAddress` | String | Unique wallet address (lowercase, indexed). |
| `username` | String | Farcaster or custom username. |
| `displayName` | String | User's display name (required). |
| `pfpUrl` | String | URL to the profile picture. |
| `totalPoints` | Number | Total points earned by the user (default: 0). |
| `puzzlesSolved` | Number | Number of puzzles solved (default: 0). |
| `lastLogin` | Date | Timestamp of the last login (default: now). |
| `currentStreak` | Number | Current daily login/solve streak (default: 1). |
| `longestStreak` | Number | Longest streak achieved by the user (default: 1). |
| `totalPuzzlesSolved` | Number | Total puzzles solved (redundant with `puzzlesSolved`?). |
| `lastPuzzleDate` | String | Date of the last puzzle solved (format: YYYY-MM-DD). |
| `settings` | Object | User-specific settings. |
| `settings.ratingRange.min` | Number | Minimum puzzle rating for random puzzles (default: 800). |
| `settings.ratingRange.max` | Number | Maximum puzzle rating for random puzzles (default: 2000). |
| `settings.disabledThemes` | [String] | List of puzzle themes the user has disabled. |

---

## DailyChallenge
Stores information about the daily puzzle challenge.

| Field | Type | Description |
| :--- | :--- | :--- |
| `utcDay` | Number | The unique day identifier (required, unique index). |
| `puzzle` | Object | The puzzle data for the challenge. |
| `puzzle.puzzleId` | String | Lichess puzzle ID. |
| `puzzle.fen` | String | FEN string representing the starting position. |
| `puzzle.rating` | Number | Difficulty rating of the puzzle. |
| `puzzle.ratingDeviation` | Number | Rating deviation of the puzzle. |
| `puzzle.moves` | [String] | Array of moves in UCI format. |
| `puzzle.themes` | [String] | Themes associated with the puzzle. |
| `activeReservationCount` | Number | Number of active reservations for this challenge. |
| `maxDailyCheckInsSnapshot` | Number | Snapshot of the max allowed check-ins for this day. |
| `checkInAmountWeiSnapshot` | String | Snapshot of the reward amount in Wei for this day. |
| `createdByWallet` | String | Wallet address of the admin who created the challenge. |
| `createdAt` | Date | Timestamp of creation (auto-managed). |
| `updatedAt` | Date | Timestamp of last update (auto-managed). |

---

## CheckInReservation
Tracks user attempts and reward claims for the daily challenge.

| Field | Type | Description |
| :--- | :--- | :--- |
| `walletAddress` | String | User's wallet address (lowercase). |
| `utcDay` | Number | The day of the challenge. |
| `dailyChallengeId` | ObjectId | Reference to the `DailyChallenge` model. |
| `deviceFingerprint` | String | Unique device identifier to prevent multiple rewards. |
| `puzzleId` | String | The puzzle ID for the reservation. |
| `status` | String | Status: `pending`, `earned`, `claiming`, `claimed`, `expired`, `failed`. |
| `rewardEligible` | Boolean | Whether the user is eligible for a reward. |
| `countsTowardSlots` | Boolean | Whether this reservation consumes a daily slot. |
| `checkInAmountWei` | String | The reward amount at the time of reservation. |
| `pendingExpiresAt` | Date | When the reservation expires if not solved. |
| `solvedAt` | Date | When the user successfully solved the puzzle. |
| `claimNonce` | String | Unique nonce for the claim transaction (sparse index). |
| `claimDeadline` | Number | Deadline for claiming the reward. |
| `claimSignature` | String | Admin signature for reward claiming. |
| `claimTxHash` | String | Hash of the claim transaction on-chain. |
| `claimedAt` | Date | When the reward was successfully claimed on-chain. |
| `errorMessage` | String | Error message if the claim or solve failed. |
| `createdAt` | Date | Timestamp of creation (auto-managed). |
| `updatedAt` | Date | Timestamp of last update (auto-managed). |

---

## FarcasterNotificationToken
Stores Farcaster notification tokens for push notifications.

| Field | Type | Description |
| :--- | :--- | :--- |
| `token` | String | Unique notification token (required, indexed). |
| `notificationUrl` | String | URL to send notifications to. |
| `fid` | Number | Farcaster ID (FID) of the user (indexed). |
| `lastEvent` | String | Last event type that triggered a notification. |
| `enabled` | Boolean | Whether notifications are enabled (default: true). |
| `lastPayload` | Mixed | Last payload sent to the notification service. |
| `jfsHeader` | String | JFS header for authentication. |
| `jfsPayload` | String | JFS payload for authentication. |
| `jfsSignature` | String | JFS signature for authentication. |
| `createdAt` | Date | Timestamp of creation (auto-managed). |
| `updatedAt` | Date | Timestamp of last update (auto-managed). |

---

## Payment
Records payments made by users (e.g., for premium features or funding).

| Field | Type | Description |
| :--- | :--- | :--- |
| `walletAddress` | String | Payer's wallet address (lowercase). |
| `paymentType` | String | Type of payment (from `PaymentType` enum). |
| `transactionHash` | String | On-chain transaction hash (unique, required). |
| `amount` | String | Amount paid (in Wei or base units). |
| `chainId` | Number | Chain ID where the payment occurred. |
| `recipient` | String | Recipient address of the payment. |
| `verified` | Boolean | Whether the transaction has been verified (default: false). |
| `createdAt` | Date | Timestamp of the payment record. |
| `expiresAt` | Date | Expiration date (if applicable). |

---

## UserPuzzle
Tracks individual puzzle attempts and completions.

| Field | Type | Description |
| :--- | :--- | :--- |
| `userWalletAddress` | String | User's wallet address. |
| `puzzleId` | String | Lichess puzzle ID. |
| `completed` | Boolean | Whether the puzzle was solved successfully (default: false). |
| `attempts` | Number | Number of attempts made (default: 0). |
| `type` | String | Type: `solve` (random) or `daily`. |
| `points` | Number | Points earned for this puzzle. |
| `solvedAt` | Date | Timestamp of when the puzzle was solved. |
| `createdAt` | Date | Timestamp of record creation. |
