/*---------------------------------------------------------------------------*\
  =========                 |
  \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
   \\    /   O peration     | Website:  https://openfoam.org
    \\  /    A nd           | Copyright (C) 2013-2018 OpenFOAM Foundation
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

\*---------------------------------------------------------------------------*/

#include "PstreamGlobals.H"
#include "error.H"

#include <cstdlib>

// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * //

namespace Foam
{

// * * * * * * * * * * * * * * Static Data Members * * * * * * * * * * * * * //

MPI_Comm PstreamGlobals::MPI_COMM_FOAM;

// Outstanding non-blocking operations.
//! \cond fileScope
DynamicList<MPI_Request> PstreamGlobals::outstandingRequests_;
//! \endcond

//// Max outstanding non-blocking operations.
////! \cond fileScope
//int PstreamGlobals::nRequests_ = 0;
////! \endcond

// Free'd non-blocking operations.
//! \cond fileScope
//DynamicList<label> PstreamGlobals::freedRequests_;
//! \endcond

// Max outstanding message tag operations.
//! \cond fileScope
int PstreamGlobals::nTags_ = 0;
//! \endcond

// Free'd message tags
//! \cond fileScope
DynamicList<int> PstreamGlobals::freedTags_;
//! \endcond


// Allocated communicators.
//! \cond fileScope
DynamicList<MPI_Comm> PstreamGlobals::MPICommunicators_;
DynamicList<MPI_Group> PstreamGlobals::MPIGroups_;
//! \endcond

// Further pieces of split non-blocking messages, see PstreamGlobals.H
DynamicList<MPI_Request> PstreamGlobals::chunkRequests_;
DynamicList<label> PstreamGlobals::chunkOwners_;


int PstreamGlobals::chunkSize()
{
    static const int size = []()
    {
        #ifdef MSMPI_VER
        int value = 4080;
        #else
        int value = 0;
        #endif

        const char* env = ::getenv("FOAM_MPI_CHUNK_SIZE");
        if (env && *env)
        {
            value = ::atoi(env);
        }

        // A piece must be able to carry data
        return value > 0 ? value : 0;
    }();

    return size;
}


std::streamsize PstreamGlobals::chunkMax()
{
    static const std::streamsize size = []()
    {
        std::streamsize value = 131072;

        const char* env = ::getenv("FOAM_MPI_CHUNK_MAX");
        if (env && *env)
        {
            value = ::atoll(env);
        }

        return value;
    }();

    return size;
}


bool PstreamGlobals::splitMessage(const std::streamsize size)
{
    const int chunk = chunkSize();
    return chunk > 0 && chunkMax() > chunk && size >= chunk && size < chunkMax();
}


void PstreamGlobals::appendChunkRequest
(
    const label i,
    const MPI_Request request
)
{
    chunkRequests_.append(request);
    chunkOwners_.append(i);
}


void PstreamGlobals::waitChunkRequests(const label start)
{
    // Owners never decrease along the list, so ours are a tail
    label first = chunkOwners_.size();
    while (first > 0 && chunkOwners_[first - 1] >= start)
    {
        --first;
    }

    if (first < chunkRequests_.size())
    {
        if
        (
            MPI_Waitall
            (
                chunkRequests_.size() - first,
                chunkRequests_.begin() + first,
                MPI_STATUSES_IGNORE
            )
        )
        {
            FatalErrorInFunction
                << "MPI_Waitall returned with error" << Foam::endl;
        }
    }

    resetChunkRequests(start);
}


void PstreamGlobals::waitChunkRequest(const label i)
{
    forAll(chunkOwners_, j)
    {
        if (chunkOwners_[j] == i)
        {
            if (MPI_Wait(&chunkRequests_[j], MPI_STATUS_IGNORE))
            {
                FatalErrorInFunction
                    << "MPI_Wait returned with error" << Foam::endl;
            }
        }
    }
}


bool PstreamGlobals::finishedChunkRequests(const label i)
{
    bool finished = true;

    forAll(chunkOwners_, j)
    {
        if (chunkOwners_[j] == i)
        {
            int flag = 0;
            MPI_Test(&chunkRequests_[j], &flag, MPI_STATUS_IGNORE);
            finished = finished && flag;
        }
    }

    return finished;
}


void PstreamGlobals::resetChunkRequests(const label start)
{
    label first = chunkOwners_.size();
    while (first > 0 && chunkOwners_[first - 1] >= start)
    {
        --first;
    }

    chunkRequests_.setSize(first);
    chunkOwners_.setSize(first);
}


void PstreamGlobals::checkCommunicator
(
    const label comm,
    const label otherProcNo
)
{
    if
    (
        comm < 0
     || comm >= PstreamGlobals::MPICommunicators_.size()
    )
    {
        FatalErrorInFunction
            << "otherProcNo:" << otherProcNo << " : illegal communicator "
            << comm << endl
            << "Communicator should be within range 0.."
            << PstreamGlobals::MPICommunicators_.size()-1 << abort(FatalError);
    }
}


// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * //

} // End namespace Foam

// ************************************************************************* //
