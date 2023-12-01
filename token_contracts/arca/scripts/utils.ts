
import { Secp256k1PublicKey, fromB64 } from "@mysten/sui.js";
import { fromHEX } from "@mysten/bcs";
import elliptic from "elliptic";
function printSuiAddress(): void {
    console.log(`Aws Public Key x: ${process.argv[3]}, y: ${process.argv[4]}`);
    // Compress the public key
    const ec = new elliptic.ec('secp256k1');

    const pubKey = ec.keyFromPublic({x: process.argv[3], y: process.argv[4]});
    const pubPointBuffer = pubKey.getPublic(true, 'array');
    const pubKeyHex = pubPointBuffer.reduce((hex, byte) => {
        return hex + byte.toString(16).padStart(2, '0');
    }, '');
    console.log('Compressed Public Key:', pubKeyHex);

    const publicKey = new Secp256k1PublicKey(fromHEX(pubKeyHex));
    console.log('SUI Address:', publicKey.toSuiAddress());
}

async function main() {
    const args = process.argv;
    let cmd = args[2];
    if (cmd === "suiAddress") {
        printSuiAddress();
    }
}
main()