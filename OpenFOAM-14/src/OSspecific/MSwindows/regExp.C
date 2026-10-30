/*---------------------------------------------------------------------------*\
  =========                 |
  \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
   \\    /   O peration     |
    \\  /    A nd           | Copyright (C) 2011-2016 OpenFOAM Foundation
     \\/     M anipulation  |
-------------------------------------------------------------------------------
License
    This file is part of blueCAPE's unofficial mingw patches for OpenFOAM.
    For more information about these patches, visit:
         http://bluecfd.com/Core

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

Modifications
    This file is based on the original version for POSIX:
        OpenFOAM/src/OSspecific/POSIX/

    This file has been created by blueCAPE's unofficial mingw patches for
    OpenFOAM.
    For more information about these patches, visit:
        http://bluecfd.com/Core

    Modifications made:
      - Only file renaming.

\*---------------------------------------------------------------------------*/

#include "regExp.H"
#include "string.H"
#include "List.H"

// * * * * * * * * * * * * * Private Member Functions  * * * * * * * * * * * //

template<class StringType>
bool Foam::regExp::matchGrouping
(
    const std::string& str,
    List<StringType>& groups
) const
{
    if (preg_ && str.size())
    {
        std::smatch m;

        // Also verify that the entire string was matched.
        // m[0] is the entire match
        // m[1..] are the (...) sub-groups
        if (std::regex_match(str, m, *preg_))
        {
            groups.setSize(ngroups());
            label groupI = 0;

            for (size_t matchI = 1; matchI < m.size(); matchI++)
            {
                if (m[matchI].matched)
                {
                    groups[groupI] = m[matchI].str();
                }
                else
                {
                    groups[groupI].clear();
                }
                groupI++;
            }

            return true;
        }
    }

    groups.clear();
    return false;
}


// * * * * * * * * * * * * * * * * Constructors  * * * * * * * * * * * * * * //

Foam::regExp::regExp()
:
    preg_(0)
{}


Foam::regExp::regExp(const char* pattern, const bool ignoreCase)
:
    preg_(0)
{
    set(pattern, ignoreCase);
}


Foam::regExp::regExp(const std::string& pattern, const bool ignoreCase)
:
    preg_(0)
{
    set(pattern.c_str(), ignoreCase);
}


// * * * * * * * * * * * * * * * * Destructor  * * * * * * * * * * * * * * * //

Foam::regExp::~regExp()
{
    clear();
}


// * * * * * * * * * * * * * * Member Functions  * * * * * * * * * * * * * * //

void Foam::regExp::set(const char* pattern, const bool ignoreCase) const
{
    clear();

    // Avoid nullptr and zero-length patterns
    if (pattern && *pattern)
    {
        std::regex::flag_type flags = std::regex::extended;
        if (ignoreCase)
        {
            flags |= std::regex::icase;
        }

        const char* pat = pattern;

        // Check for embedded prefix for ignore-case
        // this is the only embedded prefix we support
        // - a simple check is sufficient
        if (!strncmp(pattern, "(?i)", 4))
        {
            flags |= std::regex::icase;
            pat += 4;

            // avoid zero-length patterns
            if (!*pat)
            {
                return;
            }
        }

        try
        {
            preg_ = new std::regex(pat, flags);
        }
        catch (const std::regex_error& err)
        {
            FatalErrorInFunction
                << "Failed to compile regular expression '" << pattern << "'"
                << nl << err.what()
                << exit(FatalError);
        }
    }
}


void Foam::regExp::set(const std::string& pattern, const bool ignoreCase) const
{
    return set(pattern.c_str(), ignoreCase);
}


bool Foam::regExp::clear() const
{
    if (preg_)
    {
        delete preg_;
        preg_ = 0;

        return true;
    }

    return false;
}


std::string::size_type Foam::regExp::find(const std::string& str) const
{
    if (preg_ && str.size())
    {
        std::smatch m;

        if (std::regex_search(str, m, *preg_))
        {
            return size_t(m.position(0));
        }
    }

    return string::npos;
}


bool Foam::regExp::match(const std::string& str) const
{
    if (preg_ && str.size())
    {
        // Also verify that the entire string was matched
        if (std::regex_match(str, *preg_))
        {
            return true;
        }
    }

    return false;
}


bool Foam::regExp::match
(
    const std::string& str,
    List<std::string>& groups
) const
{
    return matchGrouping(str, groups);
}


bool Foam::regExp::match
(
    const std::string& str,
    List<Foam::string>& groups
) const
{
    return matchGrouping(str, groups);
}


// * * * * * * * * * * * * * * Member Operators  * * * * * * * * * * * * * * //

void Foam::regExp::operator=(const char* pat)
{
    set(pat);
}


void Foam::regExp::operator=(const std::string& pat)
{
    set(pat);
}


// ************************************************************************* //
