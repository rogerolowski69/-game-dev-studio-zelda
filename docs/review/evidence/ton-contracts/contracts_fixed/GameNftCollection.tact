import "../contracts/constants";
import "../contracts/messages";
import "../contracts/GameNftItem";

contract GameNftCollection {
    owner: Address;
    nextItemIndex: Int as uint64; // IndexSizeBits = 64
    content: Cell;
    royaltyParams: RoyaltyParams;

    commonCode: Cell;
    commonData: Builder;

    init(owner: Address, collectionContent: Cell, royaltyParams: RoyaltyParams) {
        self.owner = owner;
        self.nextItemIndex = 0;
        self.content = collectionContent;
        self.royaltyParams = royaltyParams;

        self.commonCode = codeOf GameNftItem;
        self.commonData = beginCell()
            .storeUint(0, 3) // 0b00 - null address and 0b0 - null content cell
            .storeAddress(myAddress());
    }

    receive() {} // ignore empty messages

    // Public, payable mint — anyone (a player's connected wallet) can send
    // this with >= MintPrice attached and receive the next item, owned by
    // themselves. This is the entrypoint the bridge service's POST /mint
    // drives; see docs/superpowers/specs/2026-07-28-ton-nft-gated-zone-design.md.
    receive(msg: Mint) {
        let ctx = context();
        throwUnless(InsufficientMintPayment, ctx.value >= MintPrice);

        let itemIndex = self.nextItemIndex;
        self.nextItemIndex += 1;

        let initNFTBody: Cell = InitNFTBody { owner: sender(), content: emptyCell() }.toCell();
        // +SendBounceIfActionFail: if the item deposit can't be paid, the whole
        // mint bounces back to the buyer instead of the TON being kept.
        deploy(DeployParameters {
            value: ItemDeployAmount,
            body: initNFTBody,
            init: StateInit { code: self.commonCode, data: self.commonData.storeUint(itemIndex, 64).endCell() },
            mode: SendPayFwdFeesSeparately | SendBounceIfActionFail,
        });

        // Keep a fixed storage floor in the collection and sweep everything
        // above it (MintPrice - item deposit - fees) to the owner. ReserveAtMost
        // never fails, and SendIgnoreErrors keeps a failed sweep from aborting
        // an otherwise successful mint.
        nativeReserve(minTonsForStorage, ReserveAtMost);
        message(MessageParameters {
            bounce: false,
            to: self.owner,
            value: 0,
            body: beginCell().endCell(),
            mode: SendRemainingBalance | SendIgnoreErrors,
        });
    }

    // Owner-only tooling kept from the upstream deploy flow: lets the owner
    // hand-deploy or backfill specific item indexes (e.g. recovery, airdrops)
    // without going through the public Mint price gate.
    receive(msg: DeployNFT) {
        throwUnless(IncorrectSender, sender() == self.owner);
        throwUnless(IncorrectIndex, msg.itemIndex <= self.nextItemIndex);

        deployNFTItem(self.commonCode, msg.itemIndex, msg.amount, msg.initNFTBody, self.commonData);

        if (msg.itemIndex == self.nextItemIndex) {
            self.nextItemIndex += 1;
        }
    }

    receive(msg: GetRoyaltyParams) {
        message(MessageParameters {
            bounce: false,
            to: sender(),
            value: 0,
            body: ReportRoyaltyParams {
                queryId: msg.queryId,
                params: self.royaltyParams,
            }.toCell(),
            mode: SendRemainingValue,
        });
    }

    receive(msg: BatchDeploy) {
        throwUnless(IncorrectSender, sender() == self.owner);

        let currNFTItem: DictGet = dictGetMin(msg.deployList, IndexSizeBits);
        let counter: Int = 0;

        while (currNFTItem.flag != 0) {
            counter += 1;
            throwIf(IncorrectAmount, counter >= 250); // implementation detail

            throwUnless(IncorrectIndexes + counter, currNFTItem.itemIndex!! <= self.nextItemIndex);

            let dictItem: DictItem = DictItem.fromSlice(currNFTItem.item!!);

            deployNFTItem(self.commonCode, currNFTItem.itemIndex!!, dictItem.amount, dictItem.initNFTBody, self.commonData);

            if (currNFTItem.itemIndex!! == self.nextItemIndex) {
                self.nextItemIndex += 1;
            }

            currNFTItem = dictGetNext(currNFTItem.itemIndex!!, msg.deployList, IndexSizeBits);
        }
    }

    receive(msg: ChangeOwner) {
        throwUnless(IncorrectSender, sender() == self.owner);
        self.owner = msg.newOwner;
    }

    get fun get_collection_data(): CollectionData {
        let cs: Slice = self.content.beginParse();
        return CollectionData {
            nextItemIndex: self.nextItemIndex,
            collectionContent: cs.loadRef(),
            owner: self.owner,
        };
    }

    get fun get_nft_address_by_index(index: Int): Address {
        let stateInit = initOf GameNftItem(null, null, myAddress(), index);
        return contractAddress(stateInit);
    }

    get fun royalty_params(): RoyaltyParams {
        return self.royaltyParams;
    }

    get fun get_nft_content(index: Int, individualNFTContent: Cell): Cell {
        let cs = self.content.beginParse();
        cs.skipRef();
        let commonContent = cs.loadRef().beginParse();
        return beginCell()
            .storeUint(1, 8) // off-chain tag
            .storeSlice(commonContent)
            .storeRef(individualNFTContent)
            .endCell();
    }
}

inline fun deployNFTItem(commonCode: Cell, itemIndex: Int, amount: Int, initNFTBody: Cell, commonData: Builder) {
    let data: Cell = commonData.storeUint(itemIndex, 64).endCell(); // IndexSizeBits = 64

    deploy(DeployParameters {
        value: amount,
        body: initNFTBody,
        init: StateInit { code: commonCode, data },
        mode: SendPayFwdFeesSeparately,
    });
}

struct DictGet {
    itemIndex: Int? as uint64; // IndexSizeBits = 64
    item: Slice?;
    flag: Int;
}

struct DictItem {
    amount: Int as coins;
    initNFTBody: Cell;
}

asm(-> 1 0 2) fun dictGetMin(dict: Cell, keySize: Int): DictGet { DICTUMIN NULLSWAPIFNOT2 }

asm(-> 1 0 2) fun dictGetNext(pivot: Int, dict: Cell, keySize: Int): DictGet { DICTUGETNEXT NULLSWAPIFNOT2 }
