// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChessPuzzlesStore} from "../src/ChessPuzzlesStore.sol";

contract ChessPuzzlesStoreTest is Test {
    ChessPuzzlesStore public store;
    address public admin = address(1);
    address public server = address(2);
    address public user = address(3);

    function setUp() public {
        store = new ChessPuzzlesStore(admin, server);
    }

    function testSetDailyPuzzle() public {
        vm.prank(server);
        store.setDailyPuzzle(20240424, "p1", 100, 1000);

        (string memory puzzleId, uint256 rewardAmount, uint256 maxCheckIns) = store.dailyPuzzles(20240424);
        
        assertEq(puzzleId, "p1");
        assertEq(rewardAmount, 100);
        assertEq(maxCheckIns, 1000);
    }

    function testSetReservation() public {
        vm.prank(server);
        store.setReservation(20240424, user, ChessPuzzlesStore.ReservationStatus.Pending, 100, 0);

        (ChessPuzzlesStore.ReservationStatus status, uint256 rewardAmount, uint256 solvedAt) = store.reservations(20240424, user);
        
        assertEq(uint(status), uint(ChessPuzzlesStore.ReservationStatus.Pending));
        assertEq(rewardAmount, 100);
        assertEq(solvedAt, 0);
    }

    function testRecordPuzzleAttempt() public {
        vm.prank(server);
        store.recordPuzzleAttempt(user, "p1", true, 1, 10, 123456789);

        (bool completed, uint256 attempts, uint256 points, uint256 solvedAt) = store.puzzleAttempts("p1", user);
        
        assertTrue(completed);
        assertEq(attempts, 1);
        assertEq(points, 10);
        assertEq(solvedAt, 123456789);
    }

    function test_RevertWhen_UnauthorizedSetDailyPuzzle() public {
        vm.prank(user);
        vm.expectRevert();
        store.setDailyPuzzle(20240424, "p1", 100, 1000);
    }

    function test_RevertWhen_UnauthorizedSetReservation() public {
        vm.prank(user);
        vm.expectRevert();
        store.setReservation(20240424, user, ChessPuzzlesStore.ReservationStatus.Pending, 100, 0);
    }

    function test_RevertWhen_UnauthorizedRecordPuzzleAttempt() public {
        vm.prank(user);
        vm.expectRevert();
        store.recordPuzzleAttempt(user, "p1", true, 1, 10, 123456789);
    }

    function testAdminCanGrantRole() public {
        bytes32 serverRole = store.SERVER_ROLE();
        vm.prank(admin);
        store.grantRole(serverRole, user);

        vm.prank(user);
        store.setDailyPuzzle(20240424, "p1", 100, 1000);
        
        (string memory puzzleId,,) = store.dailyPuzzles(20240424);
        assertEq(puzzleId, "p1");
    }
}
