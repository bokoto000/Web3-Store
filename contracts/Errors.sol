// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

error ProductSerialExist(string serial);
error ProductSerialDoesntExist(string serial);
error ProductDoesntExist(uint256 productId);
error ProductBoughtBefore();
error ProductIsNotOwned();
error ProductIsOwned();

error SerialIsEmpty();
error NameIsEmpty();
error DescriptionIsEmpty();

error NoQuantityLeft();
error NotEnoughETH();
error ReturnTimeExpired();

error OffsetMoreThanProducts();
error NumberOfProductsIsZero();

error WithdrawalTooSoon();
error WithdrawExecuted();
error LastWithdrawNotExecuted();
error WithdrawCancelled();
error WithdrawNotCancelled();