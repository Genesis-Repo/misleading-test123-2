// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketplace is ERC721Holder, Ownable {
    uint256 public feePercentage;   // Fee percentage to be set by the marketplace owner
    uint256 private constant PERCENTAGE_BASE = 100;
    
    struct Listing {
        address seller;
        uint256 price;
        bool isActive;
        uint256 auctionEndTime; // Auction end time for the listing
        address highestBidder; // Address of the highest bidder
        uint256 highestBid; // Current highest bid amount
    }

    mapping(address => mapping(uint256 => Listing)) private listings;

    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTAuctionStarted(address indexed seller, uint256 indexed tokenId, uint256 minimumPrice, uint256 auctionEndTime);
    event NFTBidPlaced(address indexed bidder, uint256 indexed tokenId, uint256 bidAmount);
    event NFTAuctionEnded(address indexed seller, address indexed winner, uint256 indexed tokenId, uint256 winningBid);

    // Other existing functions and events remain the same

    // Function to start an auction for an NFT
    function startAuction(address nftContract, uint256 tokenId, uint256 minimumPrice, uint256 duration) external {
        require(minimumPrice > 0, "Minimum price must be greater than zero");
        require(duration > 0, "Auction duration must be greater than zero");

        // Transfer the NFT from the seller to the marketplace contract
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        uint256 auctionEndTime = block.timestamp + duration;

        // Create a new auction listing
        listings[nftContract][tokenId] = Listing({
            seller: msg.sender,
            price: minimumPrice,
            isActive: true,
            auctionEndTime: auctionEndTime,
            highestBidder: address(0),
            highestBid: 0
        });

        emit NFTAuctionStarted(msg.sender, tokenId, minimumPrice, auctionEndTime);
    }

    // Function to place a bid on an ongoing auction
    function placeBid(address nftContract, uint256 tokenId) external payable {
        Listing storage listing = listings[nftContract][tokenId];
        require(listing.isActive, "Auction is not active");
        require(block.timestamp < listing.auctionEndTime, "Auction has ended");
        require(msg.value > listing.highestBid, "Bid amount must be higher than current highest bid");

        // Refund the previous highest bidder
        if (listing.highestBidder != address(0)) {
            payable(listing.highestBidder).transfer(listing.highestBid);
        }

        listing.highestBidder = msg.sender;
        listing.highestBid = msg.value;

        emit NFTBidPlaced(msg.sender, tokenId, msg.value);
    }

    // Function to end an ongoing auction and transfer the NFT to the highest bidder
    function endAuction(address nftContract, uint256 tokenId) external {
        Listing storage listing = listings[nftContract][tokenId];
        require(listing.isActive, "Auction is not active");
        require(block.timestamp >= listing.auctionEndTime, "Auction is still ongoing");

        // Transfer the NFT to the winner
        IERC721(nftContract).safeTransferFrom(address(this), listing.highestBidder, tokenId);

        // Transfer the remaining amount to the seller after deducting fee
        uint256 feeAmount = (listing.highestBid * feePercentage) / PERCENTAGE_BASE;
        uint256 sellerAmount = listing.highestBid - feeAmount;
        payable(owner()).transfer(feeAmount); // Transfer fee to marketplace owner
        payable(listing.seller).transfer(sellerAmount);

        // Update the listing
        listing.isActive = false;

        emit NFTAuctionEnded(listing.seller, listing.highestBidder, tokenId, listing.highestBid);
    }
}