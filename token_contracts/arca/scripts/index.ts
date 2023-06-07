import {config} from "dotenv";
config();

import {
  JsonRpcProvider,
  RawSigner,
  SignerWithProvider,
  devnetConnection,
  testnetConnection,
  mainnetConnection,
  Ed25519Keypair,
} from "@mysten/sui.js";
import { publishPackage, upgradePackage } from "./commands";
import { HDSigner } from "./hdSigner";

export function getProvider(): JsonRpcProvider {
  switch (process.env.NETWORK) {
    case "devnet":
      return new JsonRpcProvider(devnetConnection);
    case "testnet":
      return new JsonRpcProvider(testnetConnection);
    case "mainnet":
      return new JsonRpcProvider(mainnetConnection);
    default:
      return new JsonRpcProvider(devnetConnection);
  }
}

async function getSigner(): Promise<SignerWithProvider> {
  // if process.env.NETWORK in ['testnet', 'devnet'], return a RawSigner
  // else return a HDSigner
  const provider = getProvider();
  if (process.env.NETWORK === "testnet" || process.env.NETWORK === "devnet") {
    if (process.env.FORCE_HD === "true") {
      return new HDSigner(provider);
    }
    return new RawSigner(
      Ed25519Keypair.fromSecretKey(Buffer.from(process.env.PRIVATE_KEY!.slice(2), "hex"), { skipValidation: true }),
      // new Ed25519Keypair({
      //   secretKey: Buffer.from(process.env.PRIVATE_KEY!),
      //   publicKey: Buffer.from(process.env.PUBLIC_KEY!),
      // }),
      provider
    );
  } else {
    return new HDSigner(provider);
  }
}
async function main() {
  // switch case arguments[0] of 'publish', 'upgrade' command
  const args = process.argv;
  //console.log(args);
  let cmd = args[2];
  const packagePath = __dirname + "/..";
  let signer = await getSigner();

  if (cmd === "publish") {
    console.log("packagePath: ", packagePath, "start to publish package");
    await publishPackage(packagePath, signer);
  } else if (cmd === "upgrade") {
    const packageId = args[3];
    const capId = args[4];
    if (!packageId || !capId) {
      console.log("packageId and capId are required");
      throw new Error("packageId and capId are required");
    }
    console.log(
      "packageId: ",
      packageId,
      "capId: ",
      capId,
      "packagePath: ",
      packagePath,
      "start to upgrade package"
    );
    await upgradePackage(packageId, capId, packagePath, signer);
  }
}
main();
