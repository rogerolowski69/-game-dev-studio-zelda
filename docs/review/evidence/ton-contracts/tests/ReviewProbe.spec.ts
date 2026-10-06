// Review probes for the economic behaviour of GameNftCollection.Mint.
// Not part of the reviewed repo: written to confirm/refute review findings.
import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Address, beginCell, fromNano, toNano } from '@ton/core';
import '@ton/test-utils';
import { GameNftCollection } from '../build/GameNftCollection/GameNftCollection_GameNftCollection';
import { GameNftItem } from '../build/GameNftItem/GameNftItem_GameNftItem';

const MINT_PRICE = toNano('0.05');

function buildContent(collectionUrl: string, itemUrl: string) {
    const collectionContent = beginCell().storeUint(1, 8).storeStringTail(collectionUrl).endCell();
    const commonContent = beginCell().storeStringTail(itemUrl).endCell();
    return beginCell().storeRef(collectionContent).storeRef(commonContent).endCell();
}

describe('review probes', () => {
    let blockchain: Blockchain;
    let owner: SandboxContract<TreasuryContract>;
    let buyer: SandboxContract<TreasuryContract>;
    let collection: SandboxContract<GameNftCollection>;

    const bal = async (a: Address) => (await blockchain.getContract(a)).balance;

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        owner = await blockchain.treasury('owner');
        buyer = await blockchain.treasury('buyer');
        const royaltyParams = { $$type: 'RoyaltyParams' as const, nominator: 0n, dominator: 100n, owner: owner.address };
        collection = blockchain.openContract(
            await GameNftCollection.fromInit(
                owner.address,
                buildContent('https://example.org/collection.json', 'https://example.org/item.json'),
                royaltyParams,
            ),
        );
        // Same funding as scripts/deploy*.ts: 0.05 TON.
        await collection.send(owner.getSender(), { value: toNano('0.05') }, null);
    });

    it('PROBE 1: collection balance across repeated mints at exactly MintPrice', async () => {
        const lines: string[] = [`after deploy: collection balance = ${fromNano(await bal(collection.address))} TON`];
        for (let i = 0; i < 5; i++) {
            const before = await bal(collection.address);
            const ownerBefore = await bal(owner.address);
            const buyerBefore = await bal(buyer.address);
            const r = await collection.send(buyer.getSender(), { value: MINT_PRICE }, { $$type: 'Mint', queryId: BigInt(i) });
            const collTx = r.transactions.find((t) => t.inMessage?.info.dest?.toString() === collection.address.toString());
            const d: any = collTx?.description;
            const data = await collection.getGetCollectionData();
            lines.push(
                `mint #${i}: compute=${d?.computePhase?.success} action=${d?.actionPhase?.success} ` +
                    `(resultCode=${d?.actionPhase?.resultCode}) aborted=${d?.aborted} | ` +
                    `collection ${fromNano(before)} -> ${fromNano(await bal(collection.address))} ` +
                    `(delta ${fromNano((await bal(collection.address)) - before)}) | ` +
                    `owner delta +${fromNano((await bal(owner.address)) - ownerBefore)} | ` +
                    `buyer delta ${fromNano((await bal(buyer.address)) - buyerBefore)} | nextItemIndex=${data.nextItemIndex}`,
            );
        }
        console.log(lines.join('\n'));
    });

    it('PROBE 2: minted item is owned by the buyer; content resolves to item.json', async () => {
        await collection.send(buyer.getSender(), { value: MINT_PRICE }, { $$type: 'Mint', queryId: 0n });
        const itemAddr = await collection.getGetNftAddressByIndex(0n);
        const item = blockchain.openContract(GameNftItem.fromAddress(itemAddr));
        const nft = await item.getGetNftData();
        const content = await collection.getGetNftContent(0n, nft.content!);
        const cs = content.beginParse();
        const tag = cs.loadUint(8);
        const url = cs.loadStringTail();
        console.log(`PROBE 2: item owner == buyer: ${nft.owner?.equals(buyer.address)}; content tag=${tag} url=${url}; item balance=${fromNano(await bal(itemAddr))}`);
        expect(nft.owner?.equals(buyer.address)).toBe(true);
    });

    it('PROBE 3: overpayment (1 TON) — where does the excess go?', async () => {
        const ownerBefore = await bal(owner.address);
        const buyerBefore = await bal(buyer.address);
        await collection.send(buyer.getSender(), { value: toNano('1') }, { $$type: 'Mint', queryId: 0n });
        console.log(
            `PROBE 3: buyer delta ${fromNano((await bal(buyer.address)) - buyerBefore)}, owner delta +${fromNano((await bal(owner.address)) - ownerBefore)}`,
        );
    });
});
