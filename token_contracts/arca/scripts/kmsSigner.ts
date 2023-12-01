import {
    SerializedSignature,
    JsonRpcProvider,
    SuiAddress,
    SignerWithProvider,
    Secp256k1PublicKey,
} from "@mysten/sui.js";
import * as dotenv from "dotenv";
const { execSync } = require('child_process');
dotenv.config();

const base64pk = process.env.KMS_BASE64PK!;
const keyId = process.env.KMS_KEY_ID!;
const cliPath: string = process.env.CLI_PATH!;

export class KmsSigner extends SignerWithProvider {
    //       this.sui = new Sui(await Transport.create());

    readonly base64Pk: string;
    readonly kmsKeyId: string;
    //readonly suiAddress: string;

    constructor(provider: JsonRpcProvider) {
        super(provider);
        this.base64Pk = base64pk;
        this.kmsKeyId = keyId;
    }

    async getPublicKey(): Promise<Secp256k1PublicKey> {
        const pk = new Secp256k1PublicKey(Buffer.from(this.base64Pk, 'base64').slice(1))
        console.log("public key of KMS wallet: ", pk.toString(), pk.toSuiAddress());
        return pk;
    }

    async getAddress(): Promise<SuiAddress> {
        return (await this.getPublicKey()).toSuiAddress();
    }

    async signData(data: Uint8Array): Promise<SerializedSignature> {

        const intent = data.slice(0, 3)
        let intentRole = ''
        for (let i = 0; i < intent.length; i++) {
            if (intent[i] > 10) {
                intentRole = intentRole + intent[i].toString()
            } else {
                intentRole = intentRole + '0' + intent[i].toString()
            }
        }
        const rawTx = data.slice(3)
        const tx_data = Buffer.from(rawTx).toString('base64')
        const { serializedSigBase64 } = JSON.parse(
            execSync(`${cliPath} keytool sign-kms --data ${tx_data} --keyid ${keyId} --base64pk ${base64pk} --intent ${intentRole} --json`),
        );


        return serializedSigBase64;
    }

    connect(provider: JsonRpcProvider): SignerWithProvider {
        return new KmsSigner(provider);
    }
}