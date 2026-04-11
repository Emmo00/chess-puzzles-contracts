import { ethers } from "ethers";

const action = process.argv[2] ?? "checkin";

const contractAddress = process.env.CLAIMS_CONTRACT;
const userAddress = process.env.USER_ADDRESS;
const serverPrivateKey = process.env.SERVER_PRIVATE_KEY;
const chainId = Number(process.env.CHAIN_ID ?? "42220");

if (!contractAddress || !userAddress || !serverPrivateKey) {
  throw new Error("Missing env vars. Required: CLAIMS_CONTRACT, USER_ADDRESS, SERVER_PRIVATE_KEY");
}

const signer = new ethers.Wallet(serverPrivateKey);

const domain = {
  name: "MiniPayPayoutClaims",
  version: "1",
  chainId,
  verifyingContract: contractAddress,
};

const types = {
  CheckInClaim: [
    { name: "user", type: "address" },
    { name: "day", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
  LeaderboardClaim: [
    { name: "user", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "claimId", type: "bytes32" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
};

function nowUnix() {
  return Math.floor(Date.now() / 1000);
}

function currentDay() {
  return Math.floor(nowUnix() / 86400);
}

function parseBigIntEnv(name, fallback) {
  const value = process.env[name];
  return BigInt(value ?? fallback);
}

async function signCheckIn() {
  const message = {
    user: userAddress,
    day: parseBigIntEnv("DAY", String(currentDay())),
    nonce: parseBigIntEnv("NONCE", "1"),
    deadline: parseBigIntEnv("DEADLINE", String(nowUnix() + 600)),
  };

  const signature = await signer.signTypedData(domain, { CheckInClaim: types.CheckInClaim }, message);
  const digest = ethers.TypedDataEncoder.hash(domain, { CheckInClaim: types.CheckInClaim }, message);
  const recovered = ethers.recoverAddress(digest, signature);

  console.log(
    JSON.stringify(
      {
        action: "checkin",
        signer: signer.address,
        recovered,
        domain,
        message,
        signature,
      },
      null,
      2
    )
  );
}

async function signLeaderboard() {
  const message = {
    user: userAddress,
    amount: parseBigIntEnv("AMOUNT", "1000000000000000000"),
    claimId: process.env.CLAIM_ID ?? ethers.hexlify(ethers.randomBytes(32)),
    nonce: parseBigIntEnv("NONCE", "1"),
    deadline: parseBigIntEnv("DEADLINE", String(nowUnix() + 600)),
  };

  const signature = await signer.signTypedData(domain, { LeaderboardClaim: types.LeaderboardClaim }, message);
  const digest = ethers.TypedDataEncoder.hash(domain, { LeaderboardClaim: types.LeaderboardClaim }, message);
  const recovered = ethers.recoverAddress(digest, signature);

  console.log(
    JSON.stringify(
      {
        action: "leaderboard",
        signer: signer.address,
        recovered,
        domain,
        message,
        signature,
      },
      null,
      2
    )
  );
}

if (action === "checkin") {
  await signCheckIn();
} else if (action === "leaderboard") {
  await signLeaderboard();
} else {
  throw new Error('Unknown action. Use "checkin" or "leaderboard"');
}