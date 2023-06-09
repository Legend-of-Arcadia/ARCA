module loa::arca{
    use std::string;
    use std::option::{Self};

    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::url;
    use multisig::multisig::{Self, MultiSignature};

    struct ARCA has drop {}

    const Decimals:u8 = 9;
    const MaxSupply:u64 = 1000000000_0000000000;

    const MintOperation: u64 = 1;
    const BurnOperation: u64 = 2;
    const UpdateMetadataOperation: u64 = 3;

    /// For when an attempting to interact with another account's Guardian.
    const ENotInMultiSigScope:u64 = 1;
    const ENotParticipant: u64 = 2;
    /// For when mint value exceed the max supply
    const EMaxSupplyExceeded: u64 = 3;
    const ENeedVote: u64 = 4;
    

    struct Guardian has key, store {
        id: UID,
        treasury_cap: TreasuryCap<ARCA>,
        for_multi_sign: ID,
    }

    struct ExtraCoinMeta has key, store {
        id: UID,
        max_supply: u64,
    }

    // ====== internal struct ======
    struct MintRequest has key, store {
        id: UID,
        amount: u64,
        recipient: address,
    }

    struct BurnRequest has key, store {
        id: UID,
        coin: Coin<ARCA>,
        creator: address,
    }

    struct UpdateMetadataRequest has key, store {
        id: UID,
        name: string::String,
        symbol: string::String,
        description: string::String,
        icon_url: string::String,
        max_supply: u64,
    }

    struct Metadata has drop {
        name: string::String,
        symbol: string::String,
        description: string::String,
        icon_url: string::String,
        max_supply: u64,
    }

    // ===== Events =====

    struct RoleGranted has copy, drop {
        cashier: address,
    }

    struct RoleRevoked has copy, drop {
        cashier: address,
    }

    struct CoinMinted has copy, drop {
        cashier: address,
        recipient: address,
        amount: u64,
    }

    struct CoinBurned has copy, drop {
        cashier: address,
    }


    fun init(witness: ARCA, tx: &mut TxContext) {
        let (treasury_cap, coin_meta) = coin::create_currency<ARCA>(witness, Decimals, b"ARCA", b"ARCA", b"ARCA Token", option::none(), tx);
        let multi_sig = multisig::create_multisig(tx);

        let guardian = Guardian {
            id: object::new(tx), 
            treasury_cap: treasury_cap, 
            for_multi_sign: object::id(&multi_sig)
        };
        transfer::public_share_object(multi_sig);
        transfer::public_share_object(coin_meta);
        transfer::share_object(guardian);
        transfer::share_object(ExtraCoinMeta{
            id: object::new(tx),
            max_supply: MaxSupply
        });

    }

    /// send mint request, wait for the multi signature result to be executed or not
    public entry fun mint_request(guardian: &mut Guardian, multi_signature : &mut MultiSignature,  extra_metadata: &ExtraCoinMeta, amount: u64, recipient: address, tx: &mut TxContext) {

        // Only multi sig guardian
        only_multi_sig_scope(multi_signature, guardian);
        // Only participant
        only_participant(multi_signature, tx);
        // check the max supply cap
        max_supply_not_exceed(guardian, extra_metadata, amount);
        let request = MintRequest{id: object::new(tx), recipient, amount};
        let desc = sui::address::to_string(object::id_address(&request));

        multisig::create_proposal(multi_signature, *string::bytes(&desc), MintOperation, request, tx);
    }

    /// execute the mint behavior while the multi signature approved
    public entry fun mint_execute(guardian: &mut Guardian,  
        multi_signature: &mut MultiSignature, 
        extra_metadata: &ExtraCoinMeta, 
        proposal_id: u256,
        is_approve: bool,
        tx: &mut TxContext
    ) : bool {
        // Only multi sig guardian
        only_multi_sig_scope(multi_signature, guardian);
        // Only participant
        only_participant(multi_signature, tx);

        if (is_approve) {
            let (approved, _ ) = multisig::is_proposal_approved(multi_signature, proposal_id);
            if (approved) {
                let request = multisig::borrow_proposal_request<MintRequest>(multi_signature, &proposal_id, tx);
                // final check for the max supply cap
                max_supply_not_exceed(guardian, extra_metadata, request.amount);
                // execute the mint action
                mint(guardian, request.amount, request.recipient, tx);
                multisig::multisig::mark_proposal_complete(multi_signature, proposal_id, tx);
                return true
            };
        }else {
            let (rejected, _ ) = multisig::is_proposal_rejected(multi_signature, proposal_id);
            if (rejected) {
                multisig::multisig::mark_proposal_complete(multi_signature, proposal_id, tx);
                return true
            }
        };
        
        abort ENeedVote
    }

    /// Mint `amount` of `Coin` and send it to `recipient`. Invokes `mint_and_transfer()`.
    fun mint(guardian: &mut Guardian, amount: u64, recipient: address, tx: &mut TxContext
    ) {
        coin::mint_and_transfer(&mut guardian.treasury_cap, amount, recipient, tx);

        event::emit(CoinMinted{
            cashier: tx_context::sender(tx), 
            recipient, 
            amount: amount,
        });

    }

    /// send mint request, wait for the multi signature result to be executed or not
    public entry fun burn_request(guardian: &mut Guardian, multi_signature : &mut MultiSignature, c: Coin<ARCA>, tx: &mut TxContext) {
        // Only multi sig guardian
        only_multi_sig_scope(multi_signature, guardian);
        // Only participant
        only_participant(multi_signature, tx);

        let request = BurnRequest{
            id: object::new(tx), 
            coin: c, 
            creator: tx_context::sender(tx)
        };

        let desc = sui::address::to_string(object::id_address(&request));
        
        multisig::create_proposal(multi_signature, *string::bytes(&desc), BurnOperation, request, tx);
    }

    /// execute the mint behavior while the multi signature approved
    public entry fun burn_execute(guardian: &mut Guardian,  
        multi_signature: &mut MultiSignature, 
        _extra_metadata: &ExtraCoinMeta, 
        proposal_id: u256, 
        is_approve: bool, 
        tx: &mut TxContext
    ) : bool {
        // Only multi sig guardian
        only_multi_sig_scope(multi_signature, guardian);
        // Only participant
        only_participant(multi_signature, tx);

        if (is_approve) {
            let (approved, _) = multisig::is_proposal_approved(multi_signature, proposal_id);
            if (approved) {
                // let BurnRequest {id, coin, creator} = multisig::extract_proposal_request<BurnRequest>(multi_signature, proposal_id, tx);
                let request = multisig::extract_proposal_request<BurnRequest>(multi_signature, proposal_id, tx);
                // burn(guardian, id, coin, creator, tx);
                burn(guardian, request, tx);
                multisig::multisig::mark_proposal_complete(multi_signature, proposal_id, tx);
                return true
            };
        } else {
            let (rejected, _) = multisig::is_proposal_rejected(multi_signature, proposal_id);
            if (rejected) {
                let BurnRequest {id, coin, creator} = multisig::extract_proposal_request<BurnRequest>(multi_signature, proposal_id, tx);
                multisig::multisig::mark_proposal_complete(multi_signature, proposal_id, tx);
                // merge back to coin
                transfer::public_transfer(coin, creator);
                object::delete(id);
                return true
            };
        };
        
        abort ENeedVote
    }

    // fun burn(guardian: &mut Guardian, id: UID, coin: Coin<ARCA>, _creator: address, tx: &mut TxContext) {
    fun burn(guardian: &mut Guardian, request: BurnRequest, tx: &mut TxContext) {
        let BurnRequest {id, coin, creator: _} = request;
        // burn to destroy the whole coin
        coin::burn(&mut guardian.treasury_cap, coin);
        object::delete(id);
        
        event::emit(CoinBurned{ cashier: tx_context::sender(tx)});
    }

    // === Update coin metadata ===

    /// Request Update partial metadata of the coin in `CoinMetadata`
    public entry fun update_metadata_request(
        guardian: &mut Guardian, 
        multi_signature : &mut MultiSignature,  
        name: string::String,
        symbol: string::String,
        description: string::String,
        icon_url: string::String,
        max_supply: u64, 
        tx: &mut TxContext
    ) {

        // Only multi sig guardian
        only_multi_sig_scope(multi_signature, guardian);
        // Only participant
        only_participant(multi_signature, tx);

        let request = UpdateMetadataRequest{
            id: object::new(tx), 
            name: name,
            symbol: symbol,
            description: description,
            icon_url: icon_url,
            max_supply: max_supply
        };

        let desc = sui::address::to_string(object::id_address(&request));

        multisig::create_proposal(
            multi_signature, *string::bytes(&desc), 
            UpdateMetadataOperation, 
            request, tx);
    }

    /// Execute Update partial metadata of the coin in `CoinMetadata`
    public entry fun update_metadata_execute(
        guardian: &mut Guardian,
        multi_signature: &mut MultiSignature, 
        metadata: &mut CoinMetadata<ARCA>, 
        extra_metadata: &mut ExtraCoinMeta,
        proposal_id: u256,
        is_approve: bool,
        tx: &mut TxContext
    ) : bool {
        // Only multi sig guardian
        only_multi_sig_scope(multi_signature, guardian);
        // Only participant
        only_participant(multi_signature, tx);

        if (is_approve) {
            // make sure proposal got approved
            let (approved, _) = multisig::is_proposal_approved(multi_signature, proposal_id);
            if (approved) {
                let request = multisig::borrow_proposal_request<UpdateMetadataRequest>(multi_signature, &proposal_id, tx);

                let metadata_request: Metadata = Metadata{
                    name: request.name,
                    symbol: request.symbol,
                    description: request.description,
                    icon_url: request.icon_url,
                    max_supply: request.max_supply, 
                };
                update_metadata(guardian, metadata, extra_metadata, metadata_request, tx);
                multisig::multisig::mark_proposal_complete(multi_signature, proposal_id, tx);
                return true
            };
        } else {
            let (rejected, _) = multisig::is_proposal_rejected(multi_signature, proposal_id);
            if (rejected) {
                multisig::multisig::mark_proposal_complete(multi_signature, proposal_id, tx);
                return true
            };
        };
        
        abort ENeedVote
    }


    /// Update partial metadata of the coin in `CoinMetadata`
    fun update_metadata(
        guardian: &Guardian, 
        metadata: &mut CoinMetadata<ARCA>, 
        extra_metadata: &mut ExtraCoinMeta,
        request: Metadata, 
        _tx: &mut TxContext) {
        if (!string::is_empty(&request.name) && coin::get_name(metadata) != request.name) {
            coin::update_name(&guardian.treasury_cap, metadata, request.name);
        };
        
        if (!string::is_empty(&request.symbol) && coin::get_symbol(metadata) != string::to_ascii(request.symbol)) {
            coin::update_symbol(&guardian.treasury_cap, metadata, string::to_ascii(request.symbol));
        };

        if (!string::is_empty(&request.description) && coin::get_description(metadata) != request.description) {
            coin::update_description(&guardian.treasury_cap, metadata, request.description);
        };

        if (!string::is_empty(&request.icon_url) 
            && (option::is_none(&coin::get_icon_url(metadata)) || option::extract(&mut coin::get_icon_url(metadata)) != url::new_unsafe(string::to_ascii(request.icon_url)))) {
            coin::update_icon_url(&guardian.treasury_cap, metadata, string::to_ascii(request.icon_url));
        };


        if (extra_metadata.max_supply != request.max_supply) {
            extra_metadata.max_supply = request.max_supply;
        };

    }

    /// Return the max supply for the Coin
    public fun get_max_supply(extra_metadata: &ExtraCoinMeta): u64 {
        extra_metadata.max_supply
    }

    // === check permission functions ===

    fun only_participant (multi_signature: &MultiSignature, tx: &mut TxContext) {
        assert!(multisig::is_participant(multi_signature, tx_context::sender(tx)), ENotParticipant);
    }

    fun only_multi_sig_scope (multi_signature: &MultiSignature, guardian: &Guardian) {
        assert!(object::id(multi_signature) == guardian.for_multi_sign, ENotInMultiSigScope);
    }

    // check the post total supply not exceed the max supply
    fun max_supply_not_exceed(guardian: &Guardian, extra_metadata: &ExtraCoinMeta, amount: u64) {
        let total_supply = coin::total_supply(&guardian.treasury_cap);
        assert!(total_supply + amount <= extra_metadata.max_supply, EMaxSupplyExceeded);
    }


    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ARCA{}, ctx);
    }

}