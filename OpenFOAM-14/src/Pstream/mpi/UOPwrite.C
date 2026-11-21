/*---------------------------------------------------------------------------*\
  =========                 |
  \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
   \\    /   O peration     | Website:  https://openfoam.org
    \\  /    A nd           | Copyright (C) 2011-2018 OpenFOAM Foundation
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

Description
    Write primitive and binary block from OPstream

\*---------------------------------------------------------------------------*/

#include "UOPstream.H"
#include "PstreamGlobals.H"

#include <mpi.h>

// * * * * * * * * * * * * * * * Member Functions  * * * * * * * * * * * * * //

bool Foam::UOPstream::write
(
    const commsTypes commsType,
    const int toProcNo,
    const char* buf,
    const std::streamsize bufSize,
    const int tag,
    const label communicator
)
{
    if (debug)
    {
        Pout<< "UOPstream::write : starting write to:" << toProcNo
            << " tag:" << tag
            << " comm:" << communicator << " size:" << label(bufSize)
            << " commsType:" << UPstream::commsTypeNames[commsType]
            << Foam::endl;
    }
    if (UPstream::warnComm != -1 && communicator != UPstream::warnComm)
    {
        Pout<< "UOPstream::write : starting write to:" << toProcNo
            << " tag:" << tag
            << " comm:" << communicator << " size:" << label(bufSize)
            << " commsType:" << UPstream::commsTypeNames[commsType]
            << " warnComm:" << UPstream::warnComm
            << Foam::endl;
        error::printStack(Pout);
    }


    PstreamGlobals::checkCommunicator(communicator, toProcNo);


    // Split a large message into pieces (see PstreamGlobals.H)
    const int chunk = PstreamGlobals::chunkSize();

    if (PstreamGlobals::splitMessage(bufSize))
    {
        if
        (
            commsType != commsTypes::blocking
         && commsType != commsTypes::scheduled
         && commsType != commsTypes::nonBlocking
        )
        {
            FatalErrorInFunction
                << "Unsupported communications type "
                << UPstream::commsTypeNames[commsType]
                << Foam::abort(FatalError);
        }

        const MPI_Comm comm = PstreamGlobals::MPICommunicators_[communicator];
        const label owner = PstreamGlobals::outstandingRequests_.size();

        bool failed = false;
        std::streamsize offset = 0;

        for (bool first = true; ; first = false)
        {
            const std::streamsize left = bufSize - offset;
            const int n = left >= chunk ? chunk : int(left);
            char* piece = const_cast<char*>(buf) + offset;

            if (commsType == commsTypes::blocking)
            {
                failed = MPI_Bsend(piece, n, MPI_BYTE, toProcNo, tag, comm)
                      || failed;
            }
            else if (commsType == commsTypes::scheduled)
            {
                failed = MPI_Send(piece, n, MPI_BYTE, toProcNo, tag, comm)
                      || failed;
            }
            else
            {
                MPI_Request request;
                failed =
                    MPI_Isend(piece, n, MPI_BYTE, toProcNo, tag, comm, &request)
                 || failed;

                if (first)
                {
                    PstreamGlobals::outstandingRequests_.append(request);
                }
                else
                {
                    PstreamGlobals::appendChunkRequest(owner, request);
                }
            }

            offset += n;

            // A short piece (possibly empty) ends the message
            if (n < chunk)
            {
                break;
            }
        }

        if (debug)
        {
            Pout<< "UOPstream::write : split write to:" << toProcNo
                << " tag:" << tag << " size:" << label(bufSize)
                << " pieces of:" << chunk
                << " commsType:" << UPstream::commsTypeNames[commsType]
                << Foam::endl;
        }

        return !failed;
    }


    bool transferFailed = true;

    if (commsType == commsTypes::blocking)
    {
        transferFailed = MPI_Bsend
        (
            const_cast<char*>(buf),
            bufSize,
            MPI_BYTE,
            toProcNo,   // procID(toProcNo),
            tag,
            PstreamGlobals::MPICommunicators_[communicator]
        );

        if (debug)
        {
            Pout<< "UOPstream::write : finished write to:" << toProcNo
                << " tag:" << tag << " size:" << label(bufSize)
                << " commsType:" << UPstream::commsTypeNames[commsType]
                << Foam::endl;
        }
    }
    else if (commsType == commsTypes::scheduled)
    {
        transferFailed = MPI_Send
        (
            const_cast<char*>(buf),
            bufSize,
            MPI_BYTE,
            toProcNo,   // procID(toProcNo),
            tag,
            PstreamGlobals::MPICommunicators_[communicator]
        );

        if (debug)
        {
            Pout<< "UOPstream::write : finished write to:" << toProcNo
                << " tag:" << tag << " size:" << label(bufSize)
                << " commsType:" << UPstream::commsTypeNames[commsType]
                << Foam::endl;
        }
    }
    else if (commsType == commsTypes::nonBlocking)
    {
        MPI_Request request;

        transferFailed = MPI_Isend
        (
            const_cast<char*>(buf),
            bufSize,
            MPI_BYTE,
            toProcNo,   // procID(toProcNo),
            tag,
            PstreamGlobals::MPICommunicators_[communicator],
            &request
        );

        if (debug)
        {
            Pout<< "UOPstream::write : started write to:" << toProcNo
                << " tag:" << tag << " size:" << label(bufSize)
                << " commsType:" << UPstream::commsTypeNames[commsType]
                << " request:" << PstreamGlobals::outstandingRequests_.size()
                << Foam::endl;
        }

        PstreamGlobals::outstandingRequests_.append(request);
    }
    else
    {
        FatalErrorInFunction
            << "Unsupported communications type "
            << UPstream::commsTypeNames[commsType]
            << Foam::abort(FatalError);
    }

    return !transferFailed;
}


// ************************************************************************* //
