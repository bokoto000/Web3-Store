// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./Errors.sol";

library Pagination {
    function getPagination(
        uint32 _length,
        uint32 _pageSize,
        uint32 _pageNumber
    )
        internal
        pure
        returns (
            uint32,
            uint32,
            uint32
        )
    {
        uint32 pages = _length / _pageSize;
        uint32 lastPage = _length - pages * _pageSize > 0 ? 1 : 0;
        uint32 pagesCount = pages + lastPage;
        if (_pageNumber > pagesCount) revert PageOutOfRange();
        uint32 end = _pageNumber * (_pageSize) < _length
            ? _pageNumber * (_pageSize)
            : _length;
        uint32 start = _pageSize * (_pageNumber - 1);
        return (start, end, pagesCount);
    }
}
