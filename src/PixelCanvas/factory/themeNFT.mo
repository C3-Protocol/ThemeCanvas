/**
 * Module     : themeNFT.mo
 * Copyright  : 2021 Hellman Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : Hellman Team - Leven
 * Stability  : Experimental
 */

import ThemeCanvas "../canvas/themeCanvas";
import IC0 "../common/IC0";
import WICP "../common/WICP";
import Types "../common/types";
import ThemeStorage "../storage/themeStorage";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Bool "mo:base/Bool";
import HashMap "mo:base/HashMap";
import Option "mo:base/Option";
import Array "mo:base/Array";
import List "mo:base/List";
import Iter "mo:base/Iter";
import Time "mo:base/Time";
import Cycles "mo:base/ExperimentalCycles";
/**
 * Factory Canister to Create Canvas Canister
 */
shared(msg)  actor class ThemeNFT (owner_: Principal, feeTo_: Principal, wicpCanisterId_: Principal) = this {

    type CreateCanvasResponse = Types.CreateCanvasResponse;
    type WICPActor = WICP.WICPActor;
    type TokenIndex = Types.TokenIndex;
    type Balance = Types.Balance;
    type MintMultiNFTRequest = Types.MintMultiNFTRequest;
    type MintThemeRequest = Types.MintThemeRequest;
    type BonusParamPercent = Types.BonusParamPercent;
    type TransferResponse = Types.TransferResponse;
    type ListRequest = Types.ListRequest;
    type ListResponse = Types.ListResponse;
    type BuyResponse = Types.BuyResponse;
    type Listings = Types.Listings;
    type SoldListings = Types.SoldListings;
    type OpRecord = Types.OpRecord;
    type Operation = Types.Operation;
    type CanvasIdentity = Types.CanvasIdentity;
    type StorageActor = Types.MultiStorageActor;

    private stable var cyclesCreateCanvas: Nat = Types.CREATECANVAS_CYCLES;
    private stable var bonusParam: BonusParamPercent = {
        feedBackPercent = 90;                           //feed fack the 90% price to prev user
        bonusWinnerPercent = 30;                       //winner get 30% bonus pool
        bonusCreatorPercent = 10;                  //creator of canvas get 10% bonus pool
        bonusAllUserPercent = 50;                       //all user get 50% bonus pool
    };

    private stable var owner: Principal = owner_;
    private stable var dimension: Nat = Types.DIMENSION;
    private stable var createThemeCanvasFee: Nat = Types.CREATEMULTICANISTER_FEE;
    private stable var basicOperatePrice: Nat = Types.THEMEBASCIOPERATING_PRICE;
    private stable var growRatio: Nat = Types.GROWRATIO;
    private stable var feeTo: Principal = feeTo_;
    private stable var WICPCanisterActor: WICPActor = actor(Principal.toText(wicpCanisterId_));

    private stable var nextTokenId : TokenIndex  = 0;
    private stable var supply : Balance  = 0;

    private stable var marketFeeRatio : Nat  = 2;
    private stable var deadline : Nat  = Types.ONE_DAY_NANOSECONDS;
    private stable var storageCanister : ?StorageActor = null;

    private stable var listingsEntries : [(TokenIndex, Listings)] = [];
    private var listings = HashMap.HashMap<TokenIndex, Listings>(1, Types.TokenIndex.equal, Types.TokenIndex.hash);

    private stable var soldListingsEntries : [(TokenIndex, SoldListings)] = [];
    private var soldListings = HashMap.HashMap<TokenIndex, SoldListings>(1, Types.TokenIndex.equal, Types.TokenIndex.hash);

    // Mapping from Canvas Index ID to Canvas-canister ID
    private stable var registryCanvasEntries : [(TokenIndex, Principal)] = [];
    private var registryCanvas = HashMap.HashMap<TokenIndex, Principal>(1, Types.TokenIndex.equal, Types.TokenIndex.hash);

    // Mapping from Canvas-canister ID to Index ID
    private stable var registryCanvasEntries2 : [(Principal, TokenIndex)] = [];
    private var registryCanvas2 = HashMap.HashMap<Principal, TokenIndex>(1, Principal.equal, Principal.hash);

    // Mapping from Index ID of all multipCanisterId
    private stable var allMultipCanvasEntries : [(TokenIndex, Principal)] = [];
    private var allMultipCanvas = HashMap.HashMap<TokenIndex, Principal>(1, Types.TokenIndex.equal, Types.TokenIndex.hash);

    // Mapping from owner to number of owned token
    private stable var balancesEntries : [(Principal, Nat)] = [];
    private var balances = HashMap.HashMap<Principal, Nat>(1, Principal.equal, Principal.hash);

    // Mapping from NFT canister ID to owner
    private stable var ownersEntries : [(TokenIndex, Principal)] = [];
    private var owners = HashMap.HashMap<TokenIndex, Principal>(1, Types.TokenIndex.equal, Types.TokenIndex.hash); 

    // Mapping from NFT canister ID to approved address
    private var nftApprovals = HashMap.HashMap<TokenIndex, Principal>(1, Types.TokenIndex.equal, Types.TokenIndex.hash); 

    // Mapping from owner to operator approvals
    private var operatorApprovals = HashMap.HashMap<Principal, HashMap.HashMap<Principal, Bool>>(1, Principal.equal, Principal.hash);

    private stable var invitedEntries : [(Principal, Bool)] = [];
    private var invited = HashMap.HashMap<Principal, Bool>(1, Principal.equal, Principal.hash);

    system func preupgrade() {
        listingsEntries := Iter.toArray(listings.entries());
        soldListingsEntries := Iter.toArray(soldListings.entries());
        registryCanvasEntries := Iter.toArray(registryCanvas.entries());
        registryCanvasEntries2 := Iter.toArray(registryCanvas2.entries());
        allMultipCanvasEntries := Iter.toArray(allMultipCanvas.entries());
        balancesEntries := Iter.toArray(balances.entries());
        ownersEntries := Iter.toArray(owners.entries());
        invitedEntries := Iter.toArray(invited.entries());
    };

    system func postupgrade() {
        balances := HashMap.fromIter<Principal, Nat>(balancesEntries.vals(), 1, Principal.equal, Principal.hash);
        owners := HashMap.fromIter<TokenIndex, Principal>(ownersEntries.vals(), 1, Types.TokenIndex.equal, Types.TokenIndex.hash);
        registryCanvas := HashMap.fromIter<TokenIndex, Principal>(registryCanvasEntries.vals(), 1, Types.TokenIndex.equal, Types.TokenIndex.hash);
        registryCanvas2 := HashMap.fromIter<Principal, TokenIndex>(registryCanvasEntries2.vals(), 1, Principal.equal, Principal.hash);
        allMultipCanvas := HashMap.fromIter<TokenIndex, Principal>(allMultipCanvasEntries.vals(), 1, Types.TokenIndex.equal, Types.TokenIndex.hash);
        listings := HashMap.fromIter<TokenIndex, Listings>(listingsEntries.vals(), 1, Types.TokenIndex.equal, Types.TokenIndex.hash);
        soldListings := HashMap.fromIter<TokenIndex, SoldListings>(soldListingsEntries.vals(), 1, Types.TokenIndex.equal, Types.TokenIndex.hash);
        invited := HashMap.fromIter<Principal, Bool>(invitedEntries.vals(), 1, Principal.equal, Principal.hash);

        listingsEntries := [];
        soldListingsEntries := [];
        balancesEntries := [];
        ownersEntries := [];
        registryCanvasEntries := [];
        registryCanvasEntries2 := [];
        allMultipCanvasEntries := [];
        invitedEntries := [];
    };

    public shared(msg) func setStorageCanisterId(storage: ?Principal) : async Bool {
        assert(msg.caller == owner);
        if (storage == null) { storageCanister := null; }
        else { storageCanister := ?actor(Principal.toText(Option.unwrap(storage))); };
        return true;
    };

    public query func getStorageCanisterId() : async ?Principal {
        var ret: ?Principal = null;
        if(storageCanister != null){
            ret := ?Principal.fromActor(Option.unwrap(storageCanister));
        };
        ret
    };

    public shared(msg) func newStorageCanister(owner: Principal) : async Bool {
        assert(msg.caller == owner and storageCanister == null);
        Cycles.add(cyclesCreateCanvas);
        let storage = await ThemeStorage.ThemeStorage(owner);
        storageCanister := ?storage;
        return true;
    };

    //create Multi-party Canvas Canister
    public shared(msg) func mintThemeCanvas(request: MintThemeRequest) : async CreateCanvasResponse {
        let bInvite = _checkInvited(msg.caller);
        if( not bInvite ){
            return #err(#NotBeInvited);
        };

        if(not _checkCyclesEnough()){
            return #err(#InsufficientCycles);
        };
        //dudect usr's WICP when create new MultiPixelCanvas
        let transferResult = await WICPCanisterActor.transferFrom(msg.caller, feeTo, createThemeCanvasFee);
        switch(transferResult){
            case(#ok(b)) {};
            case(#err(errText)){
                return #err(errText);
            };
        };
        //create new PixelCanvas and use the result canisterId to modify the member vaiable 
        Cycles.add(cyclesCreateCanvas);
        let mintRequest: MintMultiNFTRequest = {
            name = request.name;
            desc = request.desc;
            createFee = createThemeCanvasFee;
            owner = owner;
            createUser = msg.caller;
            wicpCanisterId = Principal.fromActor(WICPCanisterActor);
            tokenIndex = nextTokenId;
            dimension = dimension;
            basePrice = basicOperatePrice;
            growRatio = growRatio;
            deadline = request.deadline;
        };
        let newCanvas = await ThemeCanvas.ThemeCanvas(mintRequest, bonusParam);
        let canvasCid = Principal.fromActor(newCanvas);
        _addThemeCanvas(canvasCid);
        let info: CanvasIdentity = { 
            index=nextTokenId; 
            canisterId=canvasCid;
        };
        _addCanvas(canvasCid);
        if(storageCanister != null){
            ignore Option.unwrap(storageCanister).setParticipate(msg.caller, info);
        };
        _removeInvited(msg.caller);
        ignore _setController(canvasCid);
        return #ok(info);
    };

    public shared(msg) func setController(canisterId: Principal): async Bool {
        assert(msg.caller == owner);
        await _setController(canisterId);
        return true;
    };

    //add the PixelCanvas NFT to Owner's map when the NFT finished and product the Owner
    public shared(msg) func setNftOwner(nftOwner: Principal): async Bool {
        assert(Option.isSome(registryCanvas2.get(msg.caller)));
        
        let tokenIndex = Option.unwrap(registryCanvas2.get(msg.caller));
        owners.put(tokenIndex, nftOwner);
        balances.put( nftOwner, _balanceOf(nftOwner) + 1 );
        _removeCanisterFromMultip(tokenIndex);
        if(storageCanister != null){
            ignore Option.unwrap(storageCanister).addRecord(tokenIndex, #Mint, null, ?nftOwner, null, Time.now());
        };
        return true;
    };

    public shared(msg) func setParticipate(partner: Principal): async Bool {
        assert(Option.isSome(registryCanvas2.get(msg.caller)));
        let tokenIndex = Option.unwrap(registryCanvas2.get(msg.caller));
        let info: CanvasIdentity = { 
            index=tokenIndex; 
            canisterId=msg.caller;
        };
        if(storageCanister != null){
            ignore Option.unwrap(storageCanister).setParticipate(partner, info);
        };
        return true;
    };

    public shared(msg) func setFavorite(info: CanvasIdentity): async Bool {
        assert(Option.isSome(registryCanvas.get(info.index))
                and Option.unwrap(registryCanvas.get(info.index)) == info.canisterId);
        
        if(storageCanister != null){
            await Option.unwrap(storageCanister).setFavorite(msg.caller, info);
        };
        return true;
    };

    public shared(msg) func cancelFavorite(info: CanvasIdentity): async Bool {
        assert(Option.isSome(registryCanvas.get(info.index))
                and Option.unwrap(registryCanvas.get(info.index)) == info.canisterId);
        
        if(storageCanister != null){
            ignore Option.unwrap(storageCanister).cancelFavorite(msg.caller, info);
        };
        return true;
    };

    public shared func getCanvasStatus(canisterId: Principal): async IC0.CanisterStatus {
        assert(Option.isSome(registryCanvas2.get(canisterId)));
        let param: IC0.CanisterId = {
            canister_id = canisterId;
        };
        let status = await IC0.IC.canister_status(param);
        return status;
    };

    //modify the PixelCanvas NFT to newOwner's map when oldOwner sell the NFT to another
    public shared(msg) func transferFrom(from: Principal, to: Principal, tokenIndex: TokenIndex): async TransferResponse {
        if(Option.isSome(listings.get(tokenIndex))){
            return #err(#ListOnMarketPlace);
        };
        if( not _isApprovedOrOwner(from, msg.caller, tokenIndex) ){
            return #err(#NotOwnerOrNotApprove);
        };
        if(from == to){
            return #err(#NotAllowTransferToSelf);
        };
        _transfer(from, to, tokenIndex);
        if(Option.isSome(listings.get(tokenIndex))){
            listings.delete(tokenIndex);
        };
        return #ok(tokenIndex);
    };

    public shared(msg) func approve(approve: Principal, tokenIndex: TokenIndex): async Bool{
        assert(Option.isSome(_ownerOf(tokenIndex)) 
                and msg.caller == Option.unwrap(_ownerOf(tokenIndex)));
        nftApprovals.put(tokenIndex, approve);
        return true;
    };

    public shared(msg) func setApprovalForAll(operatored: Principal, approved: Bool): async Bool{
        assert(msg.caller != operatored);
        switch(operatorApprovals.get(msg.caller)){
            case(?op){
                op.put(operatored, approved);
                operatorApprovals.put(msg.caller, op);
            };
            case _ {
                var temp = HashMap.HashMap<Principal, Bool>(1, Principal.equal, Principal.hash);
                temp.put(operatored, approved);
                operatorApprovals.put(msg.caller, temp);
            };
        };
        return true;
    };

    public shared(msg) func setMultiFee(createMutliFee: Nat) : async Bool {
        assert(msg.caller == owner);
        createThemeCanvasFee := createMutliFee;
        return true;
    };

    public shared(msg) func setCreateCycles(cycles: Nat) : async Bool {
        assert(msg.caller == owner);
        cyclesCreateCanvas := cycles;
        return true;
    };

    public shared(msg) func setBasicPrice(newBasicPrice: Nat) : async Bool {
        assert(msg.caller == owner);
        basicOperatePrice := newBasicPrice;
        return true;
    };

    public shared(msg) func setGrowRatio(newGrowRatio: Nat) : async Bool {
        assert(msg.caller == owner);
        growRatio := newGrowRatio;
        return true;
    };
    
    public shared(msg) func setBonusParam(newBonusParam: BonusParamPercent) : async Bool {
        assert(msg.caller == owner);
        bonusParam := newBonusParam;
        return true;
    };

    public shared(msg) func setWICPCanisterId(wicpCanisterId: Principal) : async Bool {
        assert(msg.caller == owner);
        WICPCanisterActor := actor(Principal.toText(wicpCanisterId));
        return true;
    };

    public shared(msg) func setOwner(newOwner: Principal) : async Bool {
        assert(msg.caller == owner);
        owner := newOwner;
        return true;
    };

    public shared(msg) func setFeeTo(newFeeTo: Principal) : async Bool {
        assert(msg.caller == owner);
        feeTo := newFeeTo;
        return true;
    };

    public shared(msg) func setMarketFeeRatio(newRatio: Nat) : async Bool {
        assert(msg.caller == owner and marketFeeRatio < 10);
        marketFeeRatio := newRatio;
        return true;
    };

    public shared(msg) func setDeadline(newDeadline: Nat) : async Bool {
        assert(msg.caller == owner);
        deadline := newDeadline;
        return true;
    };
    
    public shared(msg) func setDimension(newDimension: Nat) : async Bool {
        assert(msg.caller == owner);
        dimension := newDimension;
        return true;
    };

    public shared(msg) func setInvited(user: [Principal]) : async Bool {
        assert(msg.caller == owner);
        for(u in user.vals()){
            invited.put(u, true);
        };
        return true;
    };

    public shared(msg) func wallet_receive() : async Nat {
        let available = Cycles.available();
        let accepted = Cycles.accept(available);
        return accepted;
    };

    public query func isList(index: TokenIndex) : async ?Listings {
        listings.get(index)
    };

    public query func getApproved(tokenIndex: TokenIndex) : async ?Principal {
        nftApprovals.get(tokenIndex)
    };

    public query func getMultiFee() : async Nat {
        createThemeCanvasFee
    };

    public query func getFeeTo() : async Principal {
        feeTo
    };

    public query func getCreateCycles() : async Nat {
        cyclesCreateCanvas
    };

    public query func getBasicPrice() : async Nat {
        basicOperatePrice
    };

    public query func getGrowRatio() : async Nat {
        growRatio
    };

    public query func getMarketFeeRatio() : async Nat {
        marketFeeRatio
    };

    public query func isApprovedForAll(owner: Principal, operatored: Principal) : async Bool {
        _checkApprovedForAll(owner, operatored)
    };

    public query func ownerOf(tokenIndex: TokenIndex) : async ?Principal {
        _ownerOf(tokenIndex)
    };

    public query func balanceOf(user: Principal) : async Nat {
        _balanceOf(user)
    };

    public query func getCycles() : async Nat {
        return Cycles.balance();
    };

    public query func getWICPCanisterId() : async Principal {
        Principal.fromActor(WICPCanisterActor)
    };

    public query func getNFTByIndex(index: TokenIndex) : async ?Principal {
        registryCanvas.get(index)
    };

    public query func getAllNFT(user: Principal) : async [(TokenIndex, Principal)] {
        var ret: [(TokenIndex, Principal)] = [];
        for((k,v) in owners.entries()){
            if(v == user){
                ret := Array.append(ret, [ (k, Option.unwrap(registryCanvas.get(k))) ] );
            };
        };
        return ret;
    };

    public query func getAllMultipCanvas() : async [(TokenIndex, Principal)] {
        let mulArr = Iter.toArray(allMultipCanvas.entries());
        Array.sort(mulArr, Types.compare)
    };

    public query func getMultipCanvasSizes() : async Nat {
        allMultipCanvas.size()
    };

    public query func getRecentFinshed() : async [CanvasIdentity] {
        var id: TokenIndex = nextTokenId;
        var ret:[CanvasIdentity] = [];
        var count = 0;

        while( id > 0 and count <= 6 ){
            if(Option.isSome(owners.get(id - 1))){
                let identity:CanvasIdentity = {
                    index = id - 1;
                    canisterId = Option.unwrap(registryCanvas.get(id - 1));
                };
                count += 1;
                ret := Array.append(ret, [identity]);
            };
            id := id - 1;
        };
        return ret;
    };

    public query func getLastTokenId() : async Nat {
        nextTokenId;
    };

    public query func getInvited(user: Principal) : async Bool {
        _checkInvited(user)
    };

    private func _checkInvited(user: Principal) : Bool {
        switch(invited.get(user)){
            case (?b){b};
            case _ {false};
        }
    };

    private func _removeInvited(user: Principal) {
        invited.delete(user);
    };

    private func _balanceOf(owner: Principal): Nat {
        var balance: Nat = 0;
        if(Option.isSome(balances.get(owner))){
            balance := Option.unwrap(balances.get(owner));
        };
        balance
    };

    private func _transfer(from: Principal, to: Principal, tokenIndex: TokenIndex) {
        balances.put( from, _balanceOf(from) - 1 );
        balances.put( to, _balanceOf(to) + 1 );
        nftApprovals.delete(tokenIndex);
        owners.put(tokenIndex, to);
    };

    private func _addSoldListings( orderInfo :Listings) {
        switch(soldListings.get(orderInfo.tokenIndex)){
            case (?sold){
                let newDeal = {
                    lastPrice = orderInfo.price;
                    time = orderInfo.time;
                    account = sold.account + 1;
                };
                soldListings.put(orderInfo.tokenIndex, newDeal);
            };
            case _ {
                let newDeal = {
                    lastPrice = orderInfo.price;
                    time = orderInfo.time;
                    account = 1;
                };
                soldListings.put(orderInfo.tokenIndex, newDeal);
            };
        };
    };

    private func _ownerOf(tokenIndex: TokenIndex) : ?Principal {
        owners.get(tokenIndex)
    };

    private func _checkOwner(tokenIndex: TokenIndex, from: Principal) : Bool {
        
        Option.isSome(owners.get(tokenIndex)) and 
        Option.unwrap(owners.get(tokenIndex)) == from
    };

    private func _checkApprove(tokenIndex: TokenIndex, approved: Principal) : Bool {
        Option.isSome(nftApprovals.get(tokenIndex)) and 
        Option.unwrap(nftApprovals.get(tokenIndex)) == approved
    };

    private func _checkApprovedForAll(owner: Principal, operatored: Principal) : Bool {
        var ret: Bool = false;
        let opAppoveMap = operatorApprovals.get(owner);
        if(Option.isNull(opAppoveMap)){ return ret; };
        let approve =  Option.unwrap(opAppoveMap).get(operatored);
        if(Option.isNull(approve)){ return ret; };
        return Option.unwrap(approve);
    };

    private func _isApprovedOrOwner(from: Principal, spender: Principal, tokenIndex: TokenIndex) : Bool {
        _checkOwner(tokenIndex, from) and (_checkOwner(tokenIndex, spender) or 
        _checkApprove(tokenIndex, spender) or _checkApprovedForAll(from, spender))
    };

    private func _setController(canisterId: Principal): async () {

        let controllers: ?[Principal] = ?[owner, Principal.fromActor(this)];
        let settings: IC0.CanisterSettings = {
            controllers = controllers;
            compute_allocation = null;
            memory_allocation = null;
            freezing_threshold = null;
        };
        let params: IC0.UpdateSettingsParams = {
            canister_id = canisterId;
            settings = settings;
        };
        await IC0.IC.update_settings(params);
    };

    private func _addCanvas(canvasCid: Principal) {
        registryCanvas.put(nextTokenId, canvasCid);
        registryCanvas2.put(canvasCid, nextTokenId);
        supply := supply + 1;
        nextTokenId := nextTokenId + 1;
    };

    private func _addThemeCanvas(canvasCid: Principal) {
        allMultipCanvas.put(nextTokenId, canvasCid);
    };

    private func _removeCanisterFromMultip(tokenIndex: TokenIndex) {
        allMultipCanvas.delete(tokenIndex);
    };

    private func _checkCyclesEnough() : Bool {
        var ret: Bool = false;
        let balance = Cycles.balance();
        if(balance > 2 * cyclesCreateCanvas){
            ret := true;
        };
        ret
    };
}
