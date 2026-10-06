// Same economics probe against the patched Mint receiver (contracts_fixed/).
import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Address, beginCell, fromNano, toNano } from '@ton/core';
import '@ton/test-utils';
import { GameNftCollection as Original } from '../build/GameNftCollection/GameNftCollection_GameNftCollection';
import { GameNftCollection as Fixed } from '../build/GameNftCollectionFixed/GameNftCollectionFixed_GameNftCollection';
import { GameNftItem } from '../build/GameNftItem/GameNftItem_GameNftItem';

const MINT_PRICE = toNano('0.05');
const content = beginCell()
    .storeRef(beginCell().storeUint(1, 8).storeStringTail('https://example.org/collection.json').endCell())
    .storeRef(beginCell().storeStringTail('https://example.org/item.json').endCell())
    .endCell();

for (const [label, C] of [['ORIGINAL', Original], ['FIXED', Fixed]] as const) {
    it(`${label}: 10 mints from a collection funded with 0.05 TON`, async () => {
        const blockchain = await Blockchain.create();
        const owner = await blockchain.treasury('owner');
        const royalty = { $$type: 'RoyaltyParams' as const, nominator: 0n, dominator: 100n, owner: owner.address };
        const collection: SandboxContract<any> = blockchain.openContract(await (C as any).fromInit(owner.address, content, royalty));
        await collection.send(owner.getSender(), { value: toNano('0.05') }, null);
        const bal = async (a: Address) => (await blockchain.getContract(a)).balance;

        let paidNothing = 0, minted = 0, bounced = 0;
        const ownerStart = await bal(owner.address);
        for (let i = 0; i < 10; i++) {
            const buyer = await blockchain.treasury(`buyer${i}`);
            const before = await bal(buyer.address);
            const r = await collection.send(buyer.getSender(), { value: MINT_PRICE }, { $$type: 'Mint', queryId: BigInt(i) });
            const spent = before - (await bal(buyer.address));
            const back = r.transactions.some((t: any) => t.inMessage?.info.dest?.equals?.(buyer.address) && t.inMessage?.info.bounced);
            if (back) bounced++;
            const itemAddr = await collection.getGetNftAddressByIndex(BigInt(minted));
            const st = (await blockchain.getContract(itemAddr)).accountState?.type;
            let gotNft = false;
            if (st === 'active') {
                const nft = await blockchain.openContract(GameNftItem.fromAddress(itemAddr)).getGetNftData();
                gotNft = !!nft.owner?.equals(buyer.address);
            }
            if (gotNft) minted++;
            else if (spent > toNano('0.01')) paidNothing++;
        }
        console.log(`${label}: minted=${minted}/10, buyers charged ~0.05 TON with NO NFT=${paidNothing}, bounced=${bounced}, ` +
            `collection balance end=${fromNano(await bal(collection.address))} TON, owner proceeds total=+${fromNano((await bal(owner.address)) - ownerStart)} TON`);
    });
}
