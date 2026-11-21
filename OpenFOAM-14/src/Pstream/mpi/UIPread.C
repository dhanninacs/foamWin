/*---------------------------------------------------------------------------*\
  =========                 |
  \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
   \\    /   O peration     | Website:  https://openfoam.org
    \\  /    A nd           | Copyright (C) 2011-2024 OpenFOAM Foundation
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
    Read from UIPstream

\*---------------------------------------------------------------------------*/

#include "UIPstream.H"
#include "PstreamGlobals.H"
#include "IOstreams.H"

#include <mpi.h>

// * * * * * * * * * * * * * Local Functions * * * * * * * * * * * * * * * //

namespace
{

// Receive a message whose size is not known in advance into buf, which grows
// to hold it, and return its size.  A split message (see PstreamGlobals.H)
// arrives as pieces of chunkSize() bytes ended by a shorter piece.
Foam::label receiveProbed
(
    const int fromProcNo,
    const int tag,
    const Foam::label comm,
    Foam::DynamicList<char>& buf
)
{
    const int chunk = Foam::PstreamGlobals::chunkSize();
    const MPI_Comm mpiComm = Foam::PstreamGlobals::MPICommunicators_[comm];

    int source = fromProcNo;
    Foam::label total = 0;
    buf.clear();

    while (true)
    {
        MPI_Status status;
        MPI_Probe(source, tag, mpiComm, &status);
        source = status.MPI_SOURCE;

        int n = 0;
        MPI_Get_count(&status, MPI_BYTE, &n);

        if (buf.capacity() < total + n)
        {
            buf.setCapacity(Foam::max(2*buf.capacity(), total + n));
        }

        if
        (
            MPI_Recv
            (
                buf.begin() + total,
                n,
                MPI_BYTE,
                source,
                tag,
                mpiComm,
                MPI_STATUS_IGNORE
            )
        )
        {
            FatalErrorInFunction
                << "MPI_Recv cannot receive incoming message"
                << Foam::abort(Foam::FatalError);
        }

        total += n;
        buf.setSize(total);

        // Only a first message of exactly chunk bytes is followed by pieces,
        // and they end with a shorter one
        if
        (
            chunk <= 0
         || Foam::PstreamGlobals::chunkMax() <= chunk
         || n != chunk
        )
        {
            break;
        }
    }

    return total;
}

} // End anonymous namespace

// * * * * * * * * * * * * * * * * Constructor * * * * * * * * * * * * * * * //

Foam::UIPstream::UIPstream
(
    const commsTypes commsType,
    const int fromProcNo,
    DynamicList<char>& externalBuf,
    label& externalBufPosition,
    const int tag,
    const label comm,
    const bool clearAtEnd,
    const streamFormat format,
    const versionNumber version,
    const bool global
)
:
    UPstream(commsType),
    Istream(format, version, UNCOMPRESSED, global),
    fromProcNo_(fromProcNo),
    externalBuf_(externalBuf),
    externalBufPosition_(externalBufPosition),
    tag_(tag),
    comm_(comm),
    clearAtEnd_(clearAtEnd),
    messageSize_(0)
{
    setOpened();
    setGood();

    if (commsType == commsTypes::nonBlocking)
    {
        // Message is already received into externalBuf
    }
    else
    {
        label wantedSize = externalBuf_.capacity();

        if (debug)
        {
            Pout<< "UIPstream::UIPstream : read from:" << fromProcNo
                << " tag:" << tag << " comm:" << comm_
                << " wanted size:" << wantedSize
                << Foam::endl;
        }


        // If the buffer size is not specified, probe the incoming message
        // and set it
        if (!wantedSize)
        {
            messageSize_ = receiveProbed(fromProcNo_, tag_, comm_, externalBuf_);

            if (debug)
            {
                Pout<< "UIPstream::UIPstream : probed size:" << messageSize_
                    << Foam::endl;
            }
        }
        else
        {
            messageSize_ = UIPstream::read
            (
                commsType,
                fromProcNo_,
                externalBuf_.begin(),
                wantedSize,
                tag_,
                comm_
            );
        }

        // Set addressed size. Leave actual allocated memory intact.
        externalBuf_.setSize(messageSize_);

        if (!messageSize_)
        {
            setEof();
        }
    }
}


Foam::UIPstream::UIPstream(const int fromProcNo, PstreamBuffers& buffers)
:
    UPstream(buffers.commsType_),
    Istream(buffers.format_, buffers.version_),
    fromProcNo_(fromProcNo),
    externalBuf_(buffers.recvBuf_[fromProcNo]),
    externalBufPosition_(buffers.recvBufPos_[fromProcNo]),
    tag_(buffers.tag_),
    comm_(buffers.comm_),
    clearAtEnd_(true),
    messageSize_(0)
{
    if
    (
        commsType() != UPstream::commsTypes::scheduled
     && !buffers.finishedSendsCalled_
    )
    {
        FatalErrorInFunction
            << "PstreamBuffers::finishedSends() never called." << endl
            << "Please call PstreamBuffers::finishedSends() after doing"
            << " all your sends (using UOPstream) and before doing any"
            << " receives (using UIPstream)" << Foam::exit(FatalError);
    }

    setOpened();
    setGood();

    if (commsType() == commsTypes::nonBlocking)
    {
        // Message is already received into externalBuf
        messageSize_ = buffers.recvBuf_[fromProcNo].size();

        if (debug)
        {
            Pout<< "UIPstream::UIPstream PstreamBuffers :"
                << " fromProcNo:" << fromProcNo
                << " tag:" << tag_ << " comm:" << comm_
                << " receive buffer size:" << messageSize_
                << Foam::endl;
        }
    }
    else
    {
        label wantedSize = externalBuf_.capacity();

        if (debug)
        {
            Pout<< "UIPstream::UIPstream PstreamBuffers :"
                << " read from:" << fromProcNo
                << " tag:" << tag_ << " comm:" << comm_
                << " wanted size:" << wantedSize
                << Foam::endl;
        }

        // If the buffer size is not specified, probe the incoming message
        // and set it
        if (!wantedSize)
        {
            messageSize_ = receiveProbed(fromProcNo_, tag_, comm_, externalBuf_);

            if (debug)
            {
                Pout<< "UIPstream::UIPstream PstreamBuffers : probed size:"
                    << messageSize_ << Foam::endl;
            }
        }
        else
        {
            messageSize_ = UIPstream::read
            (
                commsType(),
                fromProcNo_,
                externalBuf_.begin(),
                wantedSize,
                tag_,
                comm_
            );
        }

        // Set addressed size. Leave actual allocated memory intact.
        externalBuf_.setSize(messageSize_);

        if (!messageSize_)
        {
            setEof();
        }
    }
}


// * * * * * * * * * * * * * * * Member Functions  * * * * * * * * * * * * * //

Foam::label Foam::UIPstream::read
(
    const commsTypes commsType,
    const int fromProcNo,
    char* buf,
    const std::streamsize bufSize,
    const int tag,
    const label communicator
)
{
    if (debug)
    {
        Pout<< "UIPstream::read : starting read from:" << fromProcNo
            << " tag:" << tag << " comm:" << communicator
            << " wanted size:" << label(bufSize)
            << " commsType:" << UPstream::commsTypeNames[commsType]
            << Foam::endl;
    }
    if (UPstream::warnComm != -1 && communicator != UPstream::warnComm)
    {
        Pout<< "UIPstream::read : starting read from:" << fromProcNo
            << " tag:" << tag << " comm:" << communicator
            << " wanted size:" << label(bufSize)
            << " commsType:" << UPstream::commsTypeNames[commsType]
            << " warnComm:" << UPstream::warnComm
            << Foam::endl;
        error::printStack(Pout);
    }

    // A message that may have been split (see PstreamGlobals.H).  A smaller
    // buffer can only hold a message that was sent whole.
    const int chunk = PstreamGlobals::chunkSize();

    if (chunk > 0 && PstreamGlobals::chunkMax() > chunk && bufSize >= chunk)
    {
        const MPI_Comm comm = PstreamGlobals::MPICommunicators_[communicator];

        if
        (
            commsType == commsTypes::blocking
         || commsType == commsTypes::scheduled
        )
        {
            // The sender's size need not fill buf, so the first message
            // tells: exactly chunk bytes means pieces follow
            MPI_Status probed;
            MPI_Probe(fromProcNo, tag, comm, &probed);
            const int source = probed.MPI_SOURCE;

            int firstSize = 0;
            MPI_Get_count(&probed, MPI_BYTE, &firstSize);

            if (firstSize != chunk)
            {
                // Sent whole
                MPI_Status status;
                if
                (
                    MPI_Recv(buf, bufSize, MPI_BYTE, source, tag, comm, &status)
                )
                {
                    FatalErrorInFunction
                        << "MPI_Recv cannot receive incoming message"
                        << Foam::abort(FatalError);

                    return 0;
                }

                int messageSize = 0;
                MPI_Get_count(&status, MPI_BYTE, &messageSize);

                if (messageSize > bufSize)
                {
                    FatalErrorInFunction
                        << "buffer (" << label(bufSize)
                        << ") not large enough for incoming message ("
                        << messageSize << ')'
                        << Foam::abort(FatalError);
                }

                return messageSize;
            }

            // Pieces until a short one
            label total = 0;

            while (true)
            {
                const std::streamsize left = bufSize - total;
                const int wanted = left >= chunk ? chunk : int(left);

                MPI_Status status;
                if
                (
                    MPI_Recv
                    (
                        buf + total,
                        wanted,
                        MPI_BYTE,
                        source,
                        tag,
                        comm,
                        &status
                    )
                )
                {
                    FatalErrorInFunction
                        << "MPI_Recv cannot receive incoming message"
                        << Foam::abort(FatalError);

                    return 0;
                }

                int n = 0;
                MPI_Get_count(&status, MPI_BYTE, &n);
                total += n;

                if (n < chunk)
                {
                    break;
                }
            }

            if (debug)
            {
                Pout<< "UIPstream::read : finished split read from:"
                    << fromProcNo << " tag:" << tag << " read size:" << total
                    << " commsType:" << UPstream::commsTypeNames[commsType]
                    << Foam::endl;
            }

            return total;
        }
        else if
        (
            commsType == commsTypes::nonBlocking
         && PstreamGlobals::splitMessage(bufSize)
        )
        {
            // Non-blocking receives are always posted with the exact size,
            // so the pieces are known in advance
            const label owner = PstreamGlobals::outstandingRequests_.size();
            std::streamsize offset = 0;

            for (bool first = true; ; first = false)
            {
                const std::streamsize left = bufSize - offset;
                const int n = left >= chunk ? chunk : int(left);

                MPI_Request request;
                if
                (
                    MPI_Irecv
                    (
                        buf + offset,
                        n,
                        MPI_BYTE,
                        fromProcNo,
                        tag,
                        comm,
                        &request
                    )
                )
                {
                    FatalErrorInFunction
                        << "MPI_Recv cannot start non-blocking receive"
                        << Foam::abort(FatalError);

                    return 0;
                }

                if (first)
                {
                    PstreamGlobals::outstandingRequests_.append(request);
                }
                else
                {
                    PstreamGlobals::appendChunkRequest(owner, request);
                }

                offset += n;

                if (n < chunk)
                {
                    break;
                }
            }

            if (debug)
            {
                Pout<< "UIPstream::read : started split read from:"
                    << fromProcNo << " tag:" << tag
                    << " read size:" << label(bufSize)
                    << " request:" << owner << Foam::endl;
            }

            return bufSize;
        }
    }

    if (commsType == commsTypes::blocking || commsType == commsTypes::scheduled)
    {
        MPI_Status status;

        if
        (
            MPI_Recv
            (
                buf,
                bufSize,
                MPI_BYTE,
                fromProcNo,
                tag,
                PstreamGlobals::MPICommunicators_[communicator],
                &status
            )
        )
        {
            FatalErrorInFunction
                << "MPI_Recv cannot receive incoming message"
                << Foam::abort(FatalError);

            return 0;
        }


        // Check size of message read

        int messageSize;
        MPI_Get_count(&status, MPI_BYTE, &messageSize);

        if (debug)
        {
            Pout<< "UIPstream::read : finished read from:" << fromProcNo
                << " tag:" << tag << " read size:" << label(bufSize)
                << " commsType:" << UPstream::commsTypeNames[commsType]
                << Foam::endl;
        }

        if (messageSize > bufSize)
        {
            FatalErrorInFunction
                << "buffer (" << label(bufSize)
                << ") not large enough for incoming message ("
                << messageSize << ')'
                << Foam::abort(FatalError);
        }

        return messageSize;
    }
    else if (commsType == commsTypes::nonBlocking)
    {
        MPI_Request request;

        if
        (
            MPI_Irecv
            (
                buf,
                bufSize,
                MPI_BYTE,
                fromProcNo,
                tag,
                PstreamGlobals::MPICommunicators_[communicator],
                &request
            )
        )
        {
            FatalErrorInFunction
                << "MPI_Recv cannot start non-blocking receive"
                << Foam::abort(FatalError);

            return 0;
        }

        if (debug)
        {
            Pout<< "UIPstream::read : started read from:" << fromProcNo
                << " tag:" << tag << " read size:" << label(bufSize)
                << " commsType:" << UPstream::commsTypeNames[commsType]
                << " request:" << PstreamGlobals::outstandingRequests_.size()
                << Foam::endl;
        }

        PstreamGlobals::outstandingRequests_.append(request);

        // Assume the message is completely received.
        return bufSize;
    }
    else
    {
        FatalErrorInFunction
            << "Unsupported communications type "
            << int(commsType)
            << Foam::abort(FatalError);

        return 0;
    }
}


// ************************************************************************* //
