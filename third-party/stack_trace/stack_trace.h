// This code is derived from the revision 68982 from Google Chromium project.
// Copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The modifications made to work outside of the Chromium project lead to
// dropping thread safe policies, since this is targetting a single thread
// applications, namely the modified versions of OpenFOAM 1.7.x and newer,
// being done by FSD blueCAPE Lda in Portugal, from 2010 till 2017.
//
// There have been some influences in the re-adaptation from the more recent
// code in Chromium, namely from commit 19e8f3dffc38, which has the following
// marking:
//      Copyright (c) 2012 The Chromium Authors. All rights reserved.


#ifndef BASE_DEBUG_STACK_TRACE_H_
#define BASE_DEBUG_STACK_TRACE_H_
#pragma once

#include <windows.h>
#include <dbghelp.h>
#include <iosfwd>

// A stacktrace can be helpful in debugging. For example, you can include a
// stacktrace member in a object (probably around #ifndef NDEBUG) so that you
// can later see where the given object was created from.
class StackTrace {
 public:
  // Creates a stacktrace from the current location.
  StackTrace();

  // Creates a stacktrace from an existing context.
  StackTrace(const PCONTEXT pContext);

  // Creates a stacktrace for an exception.
  // Note: this function will throw an import not found (StackWalk64) exception
  // on system without dbghelp 5.1.
  StackTrace(_EXCEPTION_POINTERS* exception_pointers);

  // Copying and assignment are allowed with the default functions.

  ~StackTrace();
  
  void StackWalkContext(PCONTEXT ContextRecord);

  // Gets an array of instruction pointer values. |*count| will be set to the
  // number of elements in the returned array.
  const DWORD64* Addresses(size_t* count) const;

  // Resolves backtrace to symbols and write to stream.
  void OutputToStream(std::stringstream* os);

 private:
  // From http://msdn.microsoft.com/en-us/library/bb204633.aspx,
  // the sum of FramesToSkip and FramesToCapture must be less than 63,
  // so set it to 62. Even if on POSIX it could be a larger value, it usually
  // doesn't give much more information.
  static const int kMaxTraces = 62;

  DWORD64 trace_[kMaxTraces];
  int count_;
};

#endif  // BASE_DEBUG_STACK_TRACE_H_
