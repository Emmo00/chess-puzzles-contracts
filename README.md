# Chess Payout Claims Contracts

Foundry project for sponsored ERC20 reward claims on Celo, with EIP-712 backend signing.

## Contracts

- `src/PayoutClaims.sol`
	- Daily check-in claims (fixed amount, one claim per user per UTC day, global daily cap)
	- Leaderboard claims (variable amount, globally single-use `claimId`)
	- EIP-712 signature verification with replay protection (`usedDigests`)
	- Independent nonce domains:
		- `checkInNonces(user)` for daily check-ins
		- `leaderboardNonces(user)` for leaderboard payouts

- `src/SubscriptionReceiver.sol` (`StablecoinReceiver`)
	- ERC20 deposit receiver
	- Owner-controlled withdrawals and treasury sweeps

- `src/ChessPuzzlesStore.sol`
	- Stores daily puzzle IDs and reward metadata
	- Tracks user reservations for daily challenges
	- Records all user puzzle attempts and points
	- Restricted to authorized `SERVER_ROLE` wallets

## Claim Design

The claims contract is designed for relayed/sponsored transactions:

1. Backend reads nonce state from chain.
2. Backend signs typed data with the server signer key.
3. Relayer submits the claim transaction.
4. Contract validates signer, nonce, deadline, and replay constraints.
5. Tokens are transferred to `user`.

EIP-712 domain used by `PayoutClaims`:

- `name`: `MiniPayPayoutClaims`
- `version`: `1`
- `chainId`: deployment chain ID
- `verifyingContract`: deployed claims contract address

Typed structs:

- `CheckInClaim(address user,uint256 day,uint256 nonce,uint256 deadline)`
- `LeaderboardClaim(address user,uint256 amount,bytes32 claimId,uint256 nonce,uint256 deadline)`

## Local Setup

Install dependencies (already vendored in this repo):

```bash
forge --version
```

Build:

```bash
forge build
```

Run all tests:

```bash
forge test -vv
```

Run payout tests only:

```bash
forge test --match-contract PayoutClaimsTest -vvv
```

## Deploy PayoutClaims

Deployment script: `script/PayoutClaims.s.sol`

Required environment variables:

- `PRIVATE_KEY`: deployer key
- `PAYOUT_TOKEN`: ERC20 token used for payouts
- `SERVER_SIGNER`: backend signer address for EIP-712 claims
- `CHECK_IN_AMOUNT`: daily payout amount in token base units
- `MAX_DAILY_CHECK_INS`: max successful daily claims per UTC day
- `OWNER`: owner of the deployed contract

Example:

```bash
export PRIVATE_KEY=0x...
export PAYOUT_TOKEN=0x...
export SERVER_SIGNER=0x...
export CHECK_IN_AMOUNT=10000000000000000
export MAX_DAILY_CHECK_INS=100
export OWNER=0x...

forge script script/PayoutClaims.s.sol:PayoutClaimsScript \
	--rpc-url $RPC_URL \
	--broadcast
```

## Backend Signing Example

Example signer script: `script/ethers-signing-example.mjs`

Install `ethers` if needed:

```bash
npm install ethers
```

Required env vars for signing script:

- `CLAIMS_CONTRACT`
- `USER_ADDRESS`
- `SERVER_PRIVATE_KEY`
- Optional: `CHAIN_ID` (defaults to `42220`)

Sign a check-in payload:

```bash
node script/ethers-signing-example.mjs checkin
```

Sign a leaderboard payload:

```bash
node script/ethers-signing-example.mjs leaderboard
```

## Operational Notes

- Fund `PayoutClaims` with payout tokens before opening claims.
- If the signer key is compromised, funds can be drained; rotate signer immediately with `setServerSigner`.
- `claimId` is globally single-use for leaderboard claims.
- Daily check-in uses `day = block.timestamp / 1 days` and enforces same-day claims only.
- Owner can recover funds with `ownerWithdraw`.

## Integration Skills

Detailed integration guides for backend and frontend developers:

- [Chess Payout Claims Skill](skills/chess-payout-claims/SKILL.md): Signed claim flows and treasury operations.
- [Chess Puzzles Store Skill](skills/chess-puzzles-store/SKILL.md): Managing puzzle state and user progress.

## Useful Commands

```bash
forge fmt
forge snapshot
cast --help
```
