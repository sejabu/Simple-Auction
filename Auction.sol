// SPDX-License-Identifier: MIT
pragma solidity >0.8.2 <0.9;

/**
 * @title Auction
 * @author Bugallo Sergio
 * @dev For educational purposes only, implements an auction contract.
 * @notice Trabajo Final Buenos Aires EDP Modulo2 (ETHKIPU)   
 * Considerations about this contract:
 * 1- Only the latest valid bid from each address is recorded.
 * 2- The auction starts upon deployment.
 * 3- The auction duration must be specified at deployment, expressed in minutes.
 * 4- Bidders can withdraw amounts exceeding their bid without incurring the 2% commission, but only if they execute the withdrawal function while the auction is active.
 * 5- At the end of the auction, non-winning deposits will be returned to each bidder minus a 2% fee.
 * 6- The seller will receive the winning bid amount minus a 2% fee.
 * 7- The owner of the auction must be able to withdraw the funds stored in the contract.
*/

contract Auction {

    address public seller;                 // Auction seller address.
    address public owner;                  // Contract owner, auction administrator.
    address public maxBidder;              // Address of the bidder who placed the winning bid.

    uint256 public maxBid;                 // Winning bid.
    uint256 private minBid;                 // Minimum bid.
    uint256 private endTime;                // End of the auction.
    uint256 private auctionExtensionTime;   // Auction extension time in the event of new offers close to closing.

    address[] private bidders;              // Stores unique addresses of bidders.

    mapping(address => uint256) private Balance;  // Record accumulated offers for each address.
    mapping(address => uint256) private Bids;     // Record last offer for each address.

    uint8 private minPercentageDiff;              // % minimum difference between bids.
    bool private auctionStatus;                   // Indicates if owner has finished the auction and distributed funds.

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can run this function");
        _;
    }

    modifier isActive(){
         require(block.timestamp < endTime, "The auction finished.");
        _;
    }

    modifier isFinished(){
         require(block.timestamp >= endTime, "Auction is still active.");
        _;
    }

    event AuctionStart (address indexed owner, address indexed seller, uint256 minBid, uint256 StartTime, uint256 FinishTime);
    event NewOffer(address indexed bidder, uint256 amount);
    event PartialWithdraw (address indexed bidder, uint256 amount, uint256 timestamp);
    event AuctionFinished(address indexed winner, uint256 amount);

    /**
    * @dev Constructor to initialize the auction.
    * @param _durationInMinutes The duration of the auction in minutes.
    * @param _startBidValue The minimum bid value.
    * @param _minPercentageDiff The minimum percentage difference between bids.
    * @param _bidExtensionTimeInMinutes The bid/extension time for the auction in minutes.
    * @param _seller The address of the product seller.
    */
    constructor(uint256 _durationInMinutes, uint256 _startBidValue, uint8 _minPercentageDiff, uint256 _bidExtensionTimeInMinutes, address _seller) {
        require(_durationInMinutes > 0 && _startBidValue > 0 && _minPercentageDiff > 0 && _minPercentageDiff <=100, "Incorrect Deploy Params");
        owner = msg.sender;
        seller = _seller;
        minPercentageDiff = _minPercentageDiff;
        minBid = _startBidValue;
        endTime = block.timestamp + _durationInMinutes *60;
        auctionExtensionTime = _bidExtensionTimeInMinutes *60;
        auctionStatus = true;

        emit AuctionStart (owner, seller, minBid, block.timestamp, endTime);
    }

    /**
    * @dev Function to make a bid.
    * @notice This function allows users to make a bid in the auction.
    */
    function makeBid () external payable isActive {
        require(msg.sender != seller, "The seller can't make offers.");
        address _bidder = msg.sender;
        uint256 _bidValue = msg.value;
        require(_bidValue >= minBid && _bidValue >= maxBid*(100 + minPercentageDiff)/100, "The bid is not enough");
        if (Balance[_bidder] == 0) {
            bidders.push(_bidder);
        }
        maxBidder=_bidder;
        maxBid=_bidValue;
        Balance[_bidder] += _bidValue;
        Bids[_bidder] = _bidValue;

        // Extend the auction if less than 10 minutes remain
        if (endTime - block.timestamp < 10 minutes) {
            endTime += auctionExtensionTime;
        }
        
        emit NewOffer(_bidder, _bidValue);
    }

    /**
    * @dev Function to show the winner of the auction.
    * @return The address of the winning bidder and the amount of the winning bid.
    */
    function showWinner() external view isFinished returns (address, uint256) {
        return (maxBidder, maxBid);
    }

    /**
    * @dev Function to show all offers made in the auction.
    * @return Arrays of addresses of bidders and their respective bid amounts.
    */
    function showOffers() external view isFinished returns (address[] memory, uint256[] memory) {
        uint256 length = bidders.length;
        address[] memory uniqueBidders = new address[](length);
        uint256[] memory offers = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            uniqueBidders[i] = bidders[i];
            offers[i] = Bids[bidders[i]];
        }
        return (uniqueBidders, offers);
    }
    
    /**
    * @dev Function to finish the auction and distribute funds.
    */
    function finishAuction () external onlyOwner isFinished {
        require(maxBid!=0, "Auction finished without offers");
        require(auctionStatus, "FinishAuction already executed");
        auctionStatus = false;
        makeCloseTransfers();
        
        emit AuctionFinished(maxBidder, maxBid); 
    }

    /**
    * @dev Internal function to handle the distribution of funds at the end of the auction.
    */
    function makeCloseTransfers() private isFinished {

        // Send the winning bid to the seller minus the 2% fee
        Balance[maxBidder] = 0;
        (bool sentToSeller, ) = payable(seller).call{value: maxBid * 98 / 100}("");
        require(sentToSeller, "Failed to transfer winning bid to product seller.");

        // Return balances of non-winning bids less the 2% fee
        uint256 length = bidders.length;
        for (uint256 i = 0; i < length; i++) {
            address bidder = bidders[i];
            uint256 refundAmount = Balance[bidder] * 98 / 100;
            Balance[bidder] = 0; 
            (bool refunded, ) = payable(bidder).call{value: refundAmount}("");
            require(refunded, "Refund failed for a bidder.");
        }

        // Withdraw remaining commissions from the contract
        (bool sentToOwner, ) = payable(owner).call{value: address(this).balance}("");
        require(sentToOwner, "Failed balance withdraw.");
    }
            
    // Allows bidders to withdraw excess balances while the auction is active.
    function partialWithdraw () external isActive {
        address _bidder = msg.sender;
        require(Balance[_bidder] > Bids[_bidder], "No excess funds to withdraw.");
        uint256 refundAmount = Balance[_bidder] - Bids[_bidder];
        Balance[_bidder] -= refundAmount;
        (bool sent, ) = payable(_bidder).call{value: refundAmount}("");
        require(sent, "Failed to send Ether.");
        emit PartialWithdraw(_bidder, refundAmount, block.timestamp);
    }
}