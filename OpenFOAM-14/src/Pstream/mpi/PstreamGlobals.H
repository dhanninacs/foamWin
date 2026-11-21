/*---------------------------------------------------------------------------*\
  =========                 |
  \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
   \\    /   O peration     | Website:  https://openfoam.org
    \\  /    A nd           | Copyright (C) 2013-2020 OpenFOAM Foundation
     \\/     M anipulation  |
-------------------------------------------------------------------------------
License
    This file is part of OpenFOAM.

    OpenFOAM is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    OpenFOAM is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
    FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
    for more details.

    You should have received a copy of the GNU General Public License
    along with OpenFOAM.  If not, see <http://www.gnu.org/licenses/>.

Namespace
    Foam::PstreamGlobals

Description
    Global functions and variables for working with parallel streams,
    but principally for mpi

SourceFiles
    PstreamGlobals.C

\*---------------------------------------------------------------------------*/

#ifndef PstreamGlobals_H
#define PstreamGlobals_H

#include "DynamicList.H"

#include <ios>

#include <mpi.h>

// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * //

namespace Foam
{

/*---------------------------------------------------------------------------*\
                       Class PstreamGlobals Declaration
\*---------------------------------------------------------------------------*/

namespace PstreamGlobals
{
    extern MPI_Comm MPI_COMM_FOAM;

    extern DynamicList<MPI_Request> outstandingRequests_;

    // Message splitting (FoamWin, MS-MPI)
    //
    // MS-MPI copies a shared-memory message that does not fit one 4 KiB slot
    // with ReadProcessMemory, a system call that costs ~20-30 us on some
    // Windows installations whatever the size, against well under 1 us for
    // a message that fits.  A message of at least chunkSize() bytes and
    // less than chunkMax() bytes is therefore sent as pieces of exactly
    // chunkSize() bytes followed by one shorter piece (empty if the size is
    // a multiple), so the receiver can tell where it ends.  Pieces of one
    // message share its tag and are matched in order (MPI's non-overtaking
    // rule).  Larger messages go whole: the fixed cost no longer matters to
    // them, and many pieces queued at one receiver (a gather) would make MPI's
    // message matching slow.  A receiver that does not know the size tells
    // the cases apart by the first message: exactly chunkSize() bytes means
    // pieces follow.
    //
    // A non-blocking operation keeps a single entry in outstandingRequests_
    // (its first piece); the requests of its other pieces are kept in
    // chunkRequests_ with that entry's index in chunkOwners_, and are waited
    // for, tested and reset together with it.

    //- Piece size in bytes; 0 disables splitting.  Set by the environment
    //  variable FOAM_MPI_CHUNK_SIZE (the same on every rank); the default
    //  is 4080 with MS-MPI and 0 otherwise.
    int chunkSize();

    //- Size from which messages are sent whole again; FOAM_MPI_CHUNK_MAX,
    //  default 131072 (splitting is off unless chunkMax() > chunkSize())
    std::streamsize chunkMax();

    //- Whether a message of this size is sent in pieces
    bool splitMessage(const std::streamsize size);

    extern DynamicList<MPI_Request> chunkRequests_;
    extern DynamicList<label> chunkOwners_;

    //- Remember the request of a further piece of non-blocking operation i
    void appendChunkRequest(const label i, const MPI_Request request);

    //- Wait for the further pieces of operations i and above
    void waitChunkRequests(const label start);

    //- Wait for the further pieces of operation i
    void waitChunkRequest(const label i);

    //- Test the further pieces of operation i; true when all are done
    bool finishedChunkRequests(const label i);

    //- Forget the further pieces of operations i and above
    void resetChunkRequests(const label start);

    extern int nTags_;

    extern DynamicList<int> freedTags_;

    // Current communicators. First element will be MPI_COMM_FOAM
    extern DynamicList<MPI_Comm> MPICommunicators_;

    extern DynamicList<MPI_Group> MPIGroups_;

    void checkCommunicator(const label, const label procNo);
};


// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * //

} // End namespace Foam

// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * //

#endif

// ************************************************************************* //
