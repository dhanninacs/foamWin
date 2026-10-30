/*---------------------------------------------------------------------------*\
  =========                 |
  \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
   \\    /   O peration     | Website:  https://openfoam.org
    \\  /    A nd           | Copyright (C) 2012-2022 OpenFOAM Foundation
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

#include "writeFile.H"
#include "Time.H"
#include "polyMesh.H"

// * * * * * * * * * * * * * * Static Data Members * * * * * * * * * * * * * //

const Foam::word Foam::functionObjects::writeFile::outputPrefix
(
    "postProcessing"
);

Foam::label Foam::functionObjects::writeFile::addChars = 8;

#ifdef WIN64
// Function-object names may contain field names such as cloud:alpha. Encode
// Windows-reserved characters only for the output directory, not the object
// name used to look up fields. Escape '%' as well to keep the mapping distinct.
static Foam::word windowsOutputPrefix(const Foam::word& prefix)
{
    static const char hex[] = "0123456789ABCDEF";
    Foam::string encoded;
    for (const unsigned char c : prefix)
    {
        if (c < 32 || c == '%' || c == ':' || c == '<' || c == '>'
         || c == '"' || c == '/' || c == '\\' || c == '|' || c == '?' || c == '*')
        {
            encoded += '%';
            encoded += hex[c >> 4];
            encoded += hex[c & 15];
        }
        else
        {
            encoded += c;
        }
    }
    return Foam::word(encoded, false);
}
#endif


// * * * * * * * * * * * * Protected Member Functions  * * * * * * * * * * * //

void Foam::functionObjects::writeFile::initStream(Ostream& os) const
{
    os.setf(ios_base::scientific, ios_base::floatfield);
    os.width(charWidth());
}


Foam::fileName Foam::functionObjects::writeFile::baseFileDir() const
{
    fileName baseDir = fileObr_.time().globalPath()/outputPrefix;

    // Append mesh name if not default region
    if (isA<polyMesh>(fileObr_))
    {
        const polyMesh& mesh = refCast<const polyMesh>(fileObr_);
        if (mesh.name() != polyMesh::defaultRegion)
        {
            baseDir = baseDir/mesh.name();
        }
    }

    return baseDir;
}


Foam::fileName Foam::functionObjects::writeFile::baseTimeDir() const
{
    return baseFileDir()/prefix_/fileObr_.time().name();
}


Foam::Omanip<int> Foam::functionObjects::writeFile::valueWidth
(
    const label offset
) const
{
    return setw(IOstream::defaultPrecision() + addChars + offset);
}


// * * * * * * * * * * * * * * * * Constructors  * * * * * * * * * * * * * * //

Foam::functionObjects::writeFile::writeFile
(
    const objectRegistry& obr,
    const word& prefix
)
:
    fileObr_(obr),
    #ifdef WIN64
    prefix_(windowsOutputPrefix(prefix))
    #else
    prefix_(prefix)
    #endif
{}


// * * * * * * * * * * * * * * * * Destructor  * * * * * * * * * * * * * * * //

Foam::functionObjects::writeFile::~writeFile()
{}


// * * * * * * * * * * * * * * * Member Functions  * * * * * * * * * * * * * //

Foam::label Foam::functionObjects::writeFile::charWidth() const
{
    return IOstream::defaultPrecision() + addChars;
}


void Foam::functionObjects::writeFile::writeCommented
(
    Ostream& os,
    const string& str
) const
{
    os  << setw(1) << "#" << setw(1) << ' '
        << setf(ios_base::left) << setw(charWidth() - 2) << str.c_str();
}


void Foam::functionObjects::writeFile::writeTabbed
(
    Ostream& os,
    const string& str
) const
{
    os  << tab << setw(charWidth()) << str.c_str();
}


void Foam::functionObjects::writeFile::writeHeader
(
    Ostream& os,
    const string& str
) const
{
    os  << setw(1) << "#" << setw(1) << ' '
        << setf(ios_base::left) << setw(charWidth() - 2) << str.c_str() << nl;
}


void Foam::functionObjects::writeFile::writeTime(Ostream& os) const
{
    os  << setw(charWidth()) << fileObr_.time().name();
}


// ************************************************************************* //
