/**
 * Module     : multiCanvas.mo
 * Copyright  : 2021 Hellman Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : Hellman Team - Leven
 * Stability  : Experimental
 */

import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Text "mo:base/Text";
import Option "mo:base/Option";
import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Bool "mo:base/Bool";
import Cycles "mo:base/ExperimentalCycles";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Types "../common/types";
import WICP "../common/WICP";
import Factory "../common/factoryActor";

shared(msg) actor class ThemeCanvas(_request: Types.MintMultiNFTRequest, 
                                    _bonusParam: Types.BonusParamPercent) = this {
    
    type Pixel = Types.Pixel;
    type Position = Types.Position;
    type PixelInfo = Types.PixelInfo;
    type DrawPosRequest = Types.DrawPosRequest;
    type DrawRecord = Types.DrawRecord;
    type ThemeNFTDesInfo = Types.ThemeNFTDesInfo;
    type MultiCanvasAccInfo = Types.MultiCanvasAccInfo;
    type Color = Types.Color;
    type Result<T,E> = Result.Result<T,E>;
    type DrawResponse = Types.DrawResponse;
    type WithDrawResponse = Types.WithDrawResponse;
    type LotteryResponse = Types.LotteryResponse;
    type Asset = Types.Asset;
    type WICPActor = WICP.WICPActor;
    type FactoryActor = Factory.FactoryActor;

    private stable var request: Types.MintMultiNFTRequest = _request;
    private stable var bonusParam: Types.BonusParamPercent = _bonusParam;
                    
    private stable var isNFTOver: Bool = false;         
    private stable var createTime: Time.Time = Time.now();
    private stable var finshedTime: Time.Time = request.deadline;
    private stable var openTime: Time.Time = request.deadline;
    private stable var changeTotal: Nat = 0;
    private stable var totalWorth: Nat = request.createFee; 
    private stable var totalBonus: Nat = 0;

    private stable var WICPCanisterActor: WICPActor = actor(Principal.toText(request.wicpCanisterId));
    private stable var FactoryCanisterActor: FactoryActor = actor(Principal.toText(msg.caller));
    
    private stable var assetState : [(Principal, Asset)] = [];
    private var assets : HashMap.HashMap<Principal, Asset> = HashMap.fromIter(assetState.vals(), 0, Principal.equal, Principal.hash);
    if(Option.isNull(assets.get(request.createUser))){
        assets.put(request.createUser, {
                    invest = request.createFee;
                    income = 0;
                    withdraw = 0;
        });
    };
    private stable var paintersNum : Nat = assets.size();

    private stable var opsIndex: Nat = 0;
    private stable var lastTwentyDrawRecord: [var DrawRecord] = Array.init<DrawRecord>(20, {  painter = request.owner;
                                                                                            index = 0;
                                                                                            num = 0;
                                                                                            consume = 0;
                                                                                            memo = null;
                                                                                            updateTime = 0;});
    private stable var gapTime: Time.Time = 30000000000;
    private stable var incrementalTime: Time.Time = 360000000000;
    private stable var accUpdateTimeState : [(Principal, Time.Time)] = [];
    private var accUpdateTimes : HashMap.HashMap<Principal, Time.Time> = HashMap.fromIter(accUpdateTimeState.vals(), 0, Principal.equal, Principal.hash);

    private stable var accPixelNumsState : [(Principal, Nat)] = [];
    private var accPixelNums : HashMap.HashMap<Principal, Nat> = HashMap.fromIter(accPixelNumsState.vals(), 0, Principal.equal, Principal.hash);

    private stable var accChangeTotalNumsState : [(Principal, Nat)] = [];
    private var accChangeTotalNums : HashMap.HashMap<Principal, Nat> = HashMap.fromIter(accChangeTotalNumsState.vals(), 0, Principal.equal, Principal.hash);

    private stable var positionState : [(Position, Pixel)] = [];
    private var positions : HashMap.HashMap<Position, Pixel> = HashMap.fromIter(positionState.vals(), 0, Types.equal, Types.hash);

    private stable var pinPosState : [(Position, Bool)] = [];
    private var pinPosMap : HashMap.HashMap<Position, Bool> = HashMap.fromIter(pinPosState.vals(), 0, Types.equal, Types.hash);

    system func preupgrade() {
        assetState := Iter.toArray(assets.entries());
        pinPosState := Iter.toArray(pinPosMap.entries());

        positionState := Iter.toArray(positions.entries());
        accPixelNumsState := Iter.toArray(accPixelNums.entries());
        accChangeTotalNumsState := Iter.toArray(accChangeTotalNums.entries());
    };

    system func postupgrade() {
        assetState := [];
        pinPosState := [];

        positionState := [];
        accPixelNumsState := [];
        accChangeTotalNumsState := [];
    };

    public shared(msg) func clearUselessData(flag: Bool): async Bool {
        assert( request.owner == msg.caller);
        _clearDataAfterOver(flag);
        return true;
    };

    public shared(msg) func drawPixel(drawPosReqArray: [DrawPosRequest], memo: ?Text): async DrawResponse {
        let now: Time.Time = Time.now();
        if( now < openTime ) { return #err(#NotOpen); }; 
        if( isNFTOver ) { return #err(#NFTDrawOver); }; 
        if( not _checkMemo(memo) ) { return #err(#Other); }; 
        if( not _checkPosition(drawPosReqArray) ) { return #err(#PositionError); };
        if( not _checkGapTime(msg.caller, now) ) { return #err(#NotAttachGapTime); };

        //checkif the NFT is time to finish
        if(finshedTime < now)
        {
            switch(await _setNFTOwner()){
                case(#ok(p)) { 
                    return #err(#NFTDrawOver);
                };
                case _ { assert(false); }; //
            };
        };
        //calculate the position's curprice
        _setGapTime(msg.caller, now);
        var totalFee: Nat = 0;
        var posPixelMap = HashMap.HashMap<Position, Pixel>(1, Types.equal, Types.hash);
        for(i in Iter.range(0, drawPosReqArray.size() - 1)){
            if( Option.isNull(posPixelMap.get(drawPosReqArray[i].pos)) ){
                let pixel = _getNextPixel(drawPosReqArray[i].pos, msg.caller, drawPosReqArray[i].color);
                totalFee := totalFee + pixel.curPrice;
                posPixelMap.put(drawPosReqArray[i].pos, pixel);
            };
        };
        
        //dudect the WICP from msg.caller
        let transferResult = await WICPCanisterActor.transferFrom(msg.caller, Principal.fromActor(this), totalFee);
        switch(transferResult){
            case(#ok(b)) {};
            case(#err(errText)){
                return #err(errText);
            };
        };

        //save user and modify the postion state and whole canvas's state
        if(_addConsume(msg.caller, totalFee)){
            ignore FactoryCanisterActor.setParticipate(msg.caller);
        };

        for((k, v) in posPixelMap.entries()) {
            positions.put(k, v);
            _calAccPixelNum(v);
            //calculate the feedback and bonus
            _calFeedBack(v);
        };

        changeTotal := changeTotal + posPixelMap.size();
        totalWorth := totalWorth + totalFee;
        _addDrawRecord(msg.caller, drawPosReqArray.size(), totalFee, memo, now);
        _addAccChangeNum(msg.caller, posPixelMap.size());
        #ok(true)
    };

    public shared(msg) func withDrawLeft(): async () {
        //checkif Bonus active and msg.caller exist
        assert( request.owner == msg.caller );
        ignore _withDrawLeft();
    };

    public shared(msg) func withDrawIncome(): async WithDrawResponse {
        var txIndex = 0;
        let asset = _getAsset(msg.caller);
        if(asset.income == 0){
            return #err(#InsufficientBalance);
        };
        let transferResult = await WICPCanisterActor.transfer(msg.caller, asset.income);
        switch(transferResult){
            case(#ok(index)) {
                txIndex := index;
            };
            case(#err(errText)){
                return #err(errText);
            };
        };
        _updateAsset(msg.caller, asset.income);
        return #ok(txIndex);
    };

    //produce the nft owner
    public func lotteryNFTOwner(): async LotteryResponse {
        assert(not isNFTOver and finshedTime < Time.now());
        await _setNFTOwner()
    };

    public shared(msg) func setFinshedTime(newTime: Time.Time) : async Bool {
        assert(msg.caller == request.owner);
        finshedTime := newTime;
        return true;
    };

    public shared(msg) func setOpenTime(newTime: Time.Time) : async Bool {
        assert(msg.caller == request.owner);
        openTime := newTime;
        return true;
    };

    public shared(msg) func pinPositions(pins: [DrawPosRequest]) : async Bool {
        assert( not isNFTOver and msg.caller == request.owner);
        for(i in pins.vals()){
            pinPosMap.put(i.pos, true);
        };
        return true;
    };

    public shared(msg) func initialPixels(initials: [DrawPosRequest]) : async Bool {
        assert( not isNFTOver and msg.caller == request.owner);
        for(i in initials.vals()){
            let p: Pixel = {
                curOwner = request.owner;
                prevOwner = request.owner;
                curPrice = request.basePrice;
                color = i.color;
            };
            positions.put(i.pos, p);
        };
        accPixelNums.put(request.owner, initials.size());
        return true;
    };

    public shared(msg) func clearPinPixels() : async Bool {
        assert(msg.caller == request.createUser or msg.caller == request.owner);
        pinPosMap := HashMap.HashMap<Position, Bool>(0, Types.equal, Types.hash);
        return true;
    };

    public shared query(msg) func getAccInfo() : async MultiCanvasAccInfo {
        let asset = _getAsset(msg.caller);
        let pixelNum = _getPixelNum(msg.caller);
        let ret = {
            consume = asset.invest;
            income = asset.income;
            withDrawed = asset.withdraw;
            userBonus = 0;
            pixelNum = pixelNum;
        };
        return ret;
    };
    
    public query func getCycles() : async Nat {
        Cycles.balance()
    };

    public shared query(msg) func getAllIncome() : async [(Principal, Asset)] {
        assert(msg.caller == request.owner);
        Iter.toArray(assets.entries())
    };

    public query func getBonus() : async Nat {
        totalBonus
    };

    public query func getCreator() : async Principal {
        return request.createUser;
    };

    public query func isOver() : async Bool {
        isNFTOver
    };

    public shared(msg) func wallet_receive() : async Nat {
        let available = Cycles.available();
        let accepted = Cycles.accept(available);
        return accepted;
    };

    public query func getHighestPosition() : async ?(Position, Pixel) {
        var highestPosDesc : ?(Position, Pixel) = null;
        if(positions.size() == 0){
            return highestPosDesc;
        };
        
        let arr = Iter.toArray(positions.entries());
        highestPosDesc := ?arr[0];
        for(i in Iter.range(0, arr.size()-1)){
            if(arr[i].1.curPrice > Option.unwrap(highestPosDesc).1.curPrice){
                highestPosDesc := ?arr[i];
            };
        };
        highestPosDesc
    };

    public query func getAllPixel() : async [(Position, PixelInfo)] {
        let arr = Iter.toArray(positions.entries());
        Array.tabulate<(Position,PixelInfo)>(positions.size(), func (i) {
            let info = (arr[i].0, { color=arr[i].1.color; price=arr[i].1.curPrice });
            return (arr[i].0, { color=arr[i].1.color; price=arr[i].1.curPrice });
        })
    };

    public query func getPinPosition() : async [Position] {
        var pinPos: [var Position] = Array.init(pinPosMap.size(), {x=0;y=0});
        var index: Nat = 0;
        for((k,v) in pinPosMap.entries()){
            pinPos[index] := k;
            index += 1;
        };
        Array.freeze(pinPos)
    };

    public query func getNftDesInfo(): async ThemeNFTDesInfo {
        return _nftDesInfo();
    };

    public query func getWorth() : async Nat {
        totalWorth
    };

    public query func getFinshedTime() : async Time.Time {
        finshedTime
    };

    public query func getOpenTime() : async Time.Time {
        openTime
    };

    public query func getIncrementalTime() : async Time.Time {
        incrementalTime
    };

    public shared(msg) func setIncrementalTime(nTime: Nat) : async Bool {
        assert(msg.caller == request.owner);
        incrementalTime := nTime;
        return true;
    };

    public query func getDrawRecord() : async [DrawRecord] {
        Array.freeze(lastTwentyDrawRecord)
    };

    private func _clearDataAfterOver(flag: Bool) {
        accUpdateTimes := HashMap.HashMap<Principal, Time.Time>(0, Principal.equal, Principal.hash);
        assets := HashMap.HashMap<Principal, Asset>(0, Principal.equal, Principal.hash);
        if(flag){
            accChangeTotalNums := HashMap.HashMap<Principal, Nat>(0, Principal.equal, Principal.hash);
            accPixelNums := HashMap.HashMap<Principal, Nat>(0, Principal.equal, Principal.hash);
            pinPosMap := HashMap.HashMap<Position, Bool>(0, Types.equal, Types.hash);
        };
    };

    private func _updateAsset(user: Principal, num: Nat) {

        switch(assets.get(user)){
            case (?w){
                assets.put( user, {
                    invest = w.invest;
                    income = w.income - num;
                    withdraw = w.withdraw + num;
                });
            };
            case _ {};
        };
    };

    private func _addDrawRecord(user: Principal, size: Nat, consume: Nat, memo: ?Text, timestamp: Time.Time) {
        let recode = { painter = user;
                        index = opsIndex;
                        num = size;
                        consume = consume;
                        memo = memo;
                        updateTime = timestamp;};
        let index = opsIndex % lastTwentyDrawRecord.size();
        lastTwentyDrawRecord[index] := recode;
        opsIndex += 1;
    };

    private func _addAccChangeNum(user: Principal, changeNum: Nat) {
        switch(accChangeTotalNums.get(user)) {
            case (?n){
                accChangeTotalNums.put(user, n + changeNum);
            };
            case _ {
                accChangeTotalNums.put(user, changeNum);
            };
        };
    };

    //calculate the feedback and bonus
    private func _calFeedBack(pixel: Pixel) {
        if(pixel.curPrice > request.basePrice){
            var feedBack : Nat = Nat.div(Nat.mul(pixel.curPrice, bonusParam.feedBackPercent), 100);
            let bonus:Nat = pixel.curPrice - feedBack;
            totalBonus += bonus;

            switch(assets.get(pixel.prevOwner)){
                case (?b) {
                    assets.put(pixel.prevOwner, {
                        invest = b.invest;
                        income = b.income + feedBack;
                        withdraw = b.withdraw;
                    });
                };
                case (_) {};
            };
        } else if (pixel.curPrice == request.basePrice){
            totalBonus += request.basePrice;
        };
    };

    private func _calAccPixelNum(pixel: Pixel) {
        if(pixel.curPrice == request.basePrice){
            switch(accPixelNums.get(pixel.curOwner)){
                case (?n) { accPixelNums.put(pixel.curOwner, n + 1); };
                case _ { accPixelNums.put(pixel.curOwner, 1); };
            }
        }else if( pixel.curPrice > request.basePrice and pixel.curOwner != pixel.prevOwner ){
            switch(accPixelNums.get(pixel.curOwner), accPixelNums.get(pixel.prevOwner)){
                case (null, ?n){
                    accPixelNums.put(pixel.curOwner, 1);
                    if(n == 1){
                        accPixelNums.delete(pixel.prevOwner);
                    }else if(n > 0){
                        accPixelNums.put(pixel.prevOwner, n - 1);
                    };
                };
                case (?n, ?m){
                    accPixelNums.put(pixel.curOwner, n + 1);
                    if(m == 1){
                        accPixelNums.delete(pixel.prevOwner);
                    }else if(m > 0){
                        accPixelNums.put(pixel.prevOwner, m - 1);
                    };
                };
                case (?n, null) {
                    accPixelNums.put(pixel.curOwner, n + 1);
                };
                case (null, null) {
                    accPixelNums.put(pixel.curOwner, 1);
                };
            };
        };
    };

    private func _getPixelNum(user: Principal) : Nat {
        var num: Nat = 0;
        switch(accPixelNums.get(user)){
            case (?n) { num := n };
            case _ {};
        };
        return num;
    };

    //produce the nft owner
    private func _setNFTOwner(): async LotteryResponse {
        let success = await FactoryCanisterActor.setNftOwner(request.createUser);
        if(success){
            isNFTOver := true;
            let ret = await _dropBonus();
            if(ret){
                #ok(request.createUser)
            }else{
                #err(#BonusDropFail)
            }
        }else{
            #err(#SetOwnerFail)
        }
    };

    private func _dropBonus() : async Bool {
        let tos: [var Principal] = Array.init<Principal>(assets.size(), request.owner);
        let values: [var Nat] = Array.init<Nat>(assets.size(), 0);
        var i: Nat = 0;
        for( (k, v) in assets.entries()){
            tos[i] := k;
            values[i] := v.income;
            i := i + 1;
        };

        let transferResult = await WICPCanisterActor.batchTransfer(Array.freeze(tos), Array.freeze(values));
        switch(transferResult){
            case(#ok(b)) {
                return true;
            };
            case(#err(errText)){
                return false;
            };
        };
    };

    private func _withDrawLeft(): async () {
        let balance = await WICPCanisterActor.balanceOf(Principal.fromActor(this));
        ignore WICPCanisterActor.transfer(request.owner, balance);
    };

    private func _addConsume(user: Principal, consume: Nat) : Bool {
        var ret: Bool = false;
        switch(assets.get(user)){
            case (?b) {
                assets.put(user, {
                    invest = b.invest + consume;
                    income = b.income;
                    withdraw = b.withdraw;
                });
            };
            case (_) {
                assets.put(user, {
                    invest = consume;
                    income = 0;
                    withdraw = 0;
                });
                ret := true;
            };
        };
        paintersNum := assets.size();
        return ret;
    };

    private func _getAsset(user: Principal) : Asset {
        var asset: Asset = {
            invest = 0;
            income = 0;
            withdraw = 0;
        };
        switch(assets.get(user)){
            case (?a) {
                asset := a;
            };
            case (_) {};
        };
        asset
    };

    private func _nftDesInfo(): ThemeNFTDesInfo {
        
        var winner: ?Principal = null;

        let nftDesInfo = {
            canisterId = Principal.fromActor(this);
            createBy = request.createUser;
            name = request.name;
            desc = request.desc;
            finshTime = finshedTime;
            basePrice = request.basePrice;
            growRatio = request.growRatio;
            changeTotal = changeTotal;
            totalWorth = totalWorth;
            isNFTOver = isNFTOver;
            tokenIndex = request.tokenIndex;
            paintersNum = paintersNum;
        };
        return nftDesInfo;
    };

    private func _checkPosition(drawPosReqArray: [DrawPosRequest]): Bool {
        if(drawPosReqArray.size() == 0){
            return false;
        };
        for(i in Iter.fromArray(drawPosReqArray)) {
            if(i.pos.x >= request.dimension or i.pos.y >= request.dimension
                or Option.isSome(pinPosMap.get(i.pos))){
                return false;
            };
        };
        return true;
    };

    private func _checkMemo(memo: ?Text) : Bool {
        var ret: Bool = true;
        switch(memo){
            case (?m){
                if(m.size() > 50){
                    ret := false;
                };
            };
            case _ {};
        };
        return ret;
    };

    private func _checkGapTime(user: Principal, now: Time.Time) : Bool {
        var ret: Bool = true;
        if(Option.isSome(accUpdateTimes.get(user))
            and Option.unwrap(accUpdateTimes.get(user)) + gapTime > now){
                ret := false;
        };
        return ret;
    };

    private func _setGapTime(user: Principal, now: Time.Time) {
        accUpdateTimes.put(user, now);
    };
    
    private func _getNextPixel(pos: Position, user: Principal, color: Color) : Pixel {
        
        switch(positions.get(pos)){
            case (?pixel) {
                {
                    prevOwner = pixel.curOwner;
                    curOwner = user;
                    curPrice = Nat.div(Nat.mul(pixel.curPrice, request.growRatio), 100);
                    color = color;
                }
            };
            case (_) {
                {
                    curOwner = user;
                    prevOwner = user;
                    curPrice = request.basePrice;
                    color = color;
                }
            };
        };
    }; 
}
