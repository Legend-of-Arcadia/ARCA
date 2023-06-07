import tmp from "tmp";
import { execSync } from "child_process";

import {
  getPublishedObjectChanges,
  getExecutionStatusType,
  TransactionBlock,
  ObjectId,
  UpgradePolicy,
  SignerWithProvider,
} from "@mysten/sui.js";

console.log(process.env.SUI_BIN);
const SUI_BIN = process.env.SUI_BIN ?? "cargo run --bin sui";

export async function upgradePackage(
  packageId: ObjectId,
  capId: ObjectId,
  packagePath: string,
  signer: SignerWithProvider
) {
  // remove all controlled temporary objects on process exit
  tmp.setGracefulCleanup();

  const tmpobj = tmp.dirSync({ unsafeCleanup: true });

  const { modules, dependencies, digest } = JSON.parse(
    execSync(
      `${SUI_BIN} move build --with-unpublished-dependencies --dump-bytecode-as-base64 --path ${packagePath} --install-dir ${tmpobj.name} `,
      { encoding: "utf-8" }
    )
  );

  const tx = new TransactionBlock();

  const cap = tx.object(capId);
  const ticket = tx.moveCall({
    target: "0x2::package::authorize_upgrade",
    arguments: [cap, tx.pure(UpgradePolicy.COMPATIBLE), tx.pure(digest)],
  });

  const receipt = tx.upgrade({
    modules,
    dependencies,
    packageId,
    ticket,
  });

  tx.moveCall({
    target: "0x2::package::commit_upgrade",
    arguments: [cap, receipt],
  });

  const result = await signer.signAndExecuteTransactionBlock({
    transactionBlock: tx,
    options: {
      showEffects: true,
      showObjectChanges: true,
    },
  });
}

export async function publishPackage(
  packagePath: string,
  signer: SignerWithProvider
) {
  tmp.setGracefulCleanup();

  const tmpobj = tmp.dirSync({ unsafeCleanup: true });

  const { modules, dependencies } = JSON.parse(
    execSync(
      `${SUI_BIN} move build --with-unpublished-dependencies --dump-bytecode-as-base64 --path ${packagePath} --install-dir ${tmpobj.name}`,
      { encoding: "utf-8" }
    )
  );
  const tx = new TransactionBlock();
  const cap = tx.publish({
    modules,
    dependencies,
  });

  // Transfer the upgrade capability to the sender so they can upgrade the package later if they want.
  tx.transferObjects([cap], tx.pure(await signer.getAddress()));

  const publishTxn = await signer.signAndExecuteTransactionBlock({
    transactionBlock: tx,
    options: {
      showEffects: true,
      showObjectChanges: true,
    },
  });
  let status = getExecutionStatusType(publishTxn);
  if (status !== "success") {
    throw new Error(`Publish transaction failed with status ${status}`);
  }

  const packageId = getPublishedObjectChanges(publishTxn)[0].packageId.replace(
    /^(0x)(0+)/,
    "0x"
  ) as string;
  
  console.log("upgradeCap: ", JSON.stringify(cap));
  console.info(
    `Published package ${packageId} from address ${await signer.getAddress()}}`
  );

  return { packageId, publishTxn };
}
