// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ChessPuzzlesStore
 * @notice Stores daily puzzles, user reservations, and puzzle attempts for the chess puzzles app.
 * @dev State updates are restricted to authorized server wallets.
 */
contract ChessPuzzlesStore is AccessControl {
    bytes32 public constant SERVER_ROLE = keccak256("SERVER_ROLE");

    enum ReservationStatus {
        None,
        Pending,
        Earned,
        Claiming,
        Claimed,
        Expired,
        Failed
    }

    struct DailyPuzzle {
        string puzzleId;
        string fen;
        uint256 rating;
        string[] moves;
        uint256 rewardAmount;
        uint256 maxCheckIns;
    }

    struct CheckInReservation {
        ReservationStatus status;
        uint256 rewardAmount;
        uint256 solvedAt;
    }

    struct UserPuzzleAttempt {
        bool completed;
        uint256 attempts;
        uint256 points;
        uint256 solvedAt;
    }

    // Mapping from utcDay to DailyPuzzle info
    mapping(uint256 => DailyPuzzle) public dailyPuzzles;

    // Mapping from utcDay => userAddress => CheckInReservation
    mapping(uint256 => mapping(address => CheckInReservation)) public reservations;

    // Mapping from puzzleId => userAddress => UserPuzzleAttempt
    mapping(string => mapping(address => UserPuzzleAttempt)) public puzzleAttempts;

    event DailyPuzzleSet(uint256 indexed utcDay, string puzzleId, uint256 rating);
    event ReservationSet(uint256 indexed utcDay, address indexed user, ReservationStatus status);
    event PuzzleAttemptRecorded(string indexed puzzleId, address indexed user, bool completed);

    constructor(address admin, address initialServer) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SERVER_ROLE, initialServer);
    }

    /**
     * @notice Sets or updates the daily puzzle for a specific day.
     * @param utcDay The unique day identifier (e.g., UTC epoch day).
     * @param puzzleId Lichess puzzle ID.
     * @param fen FEN string of the starting position.
     * @param rating Difficulty rating.
     * @param moves Moves in UCI format.
     * @param rewardAmount Reward in wei for this puzzle.
     * @param maxCheckIns Max allowed check-ins for this day.
     */
    function setDailyPuzzle(
        uint256 utcDay,
        string calldata puzzleId,
        string calldata fen,
        uint256 rating,
        string[] calldata moves,
        uint256 rewardAmount,
        uint256 maxCheckIns
    ) external onlyRole(SERVER_ROLE) {
        dailyPuzzles[utcDay] = DailyPuzzle({
            puzzleId: puzzleId,
            fen: fen,
            rating: rating,
            moves: moves,
            rewardAmount: rewardAmount,
            maxCheckIns: maxCheckIns
        });
        emit DailyPuzzleSet(utcDay, puzzleId, rating);
    }

    /**
     * @notice Sets or updates a check-in reservation for a user.
     * @param utcDay The day of the challenge.
     * @param user User's wallet address.
     * @param status The current status of the reservation.
     * @param rewardAmount Snapshot of the reward amount.
     * @param solvedAt Timestamp when solved (0 if not yet solved).
     */
    function setReservation(
        uint256 utcDay,
        address user,
        ReservationStatus status,
        uint256 rewardAmount,
        uint256 solvedAt
    ) external onlyRole(SERVER_ROLE) {
        reservations[utcDay][user] = CheckInReservation({
            status: status,
            rewardAmount: rewardAmount,
            solvedAt: solvedAt
        });
        emit ReservationSet(utcDay, user, status);
    }

    /**
     * @notice Records a user's attempt on a puzzle.
     * @param user User's wallet address.
     * @param puzzleId Lichess puzzle ID.
     * @param completed Whether the puzzle was solved successfully.
     * @param attempts Number of attempts made.
     * @param points Points earned.
     * @param solvedAt Timestamp when solved.
     */
    function recordPuzzleAttempt(
        address user,
        string calldata puzzleId,
        bool completed,
        uint256 attempts,
        uint256 points,
        uint256 solvedAt
    ) external onlyRole(SERVER_ROLE) {
        puzzleAttempts[puzzleId][user] = UserPuzzleAttempt({
            completed: completed,
            attempts: attempts,
            points: points,
            solvedAt: solvedAt
        });
        emit PuzzleAttemptRecorded(puzzleId, user, completed);
    }

    /**
     * @notice Returns the moves for a specific daily puzzle.
     * @param utcDay The day of the puzzle.
     */
    function getDailyPuzzleMoves(uint256 utcDay) external view returns (string[] memory) {
        return dailyPuzzles[utcDay].moves;
    }
}
