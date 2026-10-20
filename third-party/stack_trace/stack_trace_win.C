// This code is derived from the revision 68982 from Google Chromium project.
// Most parts of the code are:
//   Copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The modifications made to work outside of the Chromium project lead to
// dropping thread safe policies, since this is targetting a single thread
// applications, namely the modified versions of OpenFOAM 1.7.x and newer,
// being done by FSD blueCAPE Lda in Portugal, from 2010 till 2017.
//
// Additional changes were made based on the example information provided here:
//     http://theorangeduck.com/page/printing-stack-trace-mingw
//
// There have been some influences in the re-adaptation from the more recent
// code in Chromium, namely from commit 19e8f3dffc38, which has the following
// marking:
//      Copyright (c) 2012 The Chromium Authors. All rights reserved.
//
// There are also code excerpts from MSDN examples, indicated in the respective
// comments in the code.

#include "stack_trace.h"

#include <sstream>
#include <iostream>
#include <iomanip>


class SymbolContext {
 public:
  static SymbolContext* GetInstance()
  {
    return new SymbolContext();
  }

  // Returns the error code of a failed initialization.
  DWORD init_error() const
  {
    return init_error_;
  }

  // For the given trace, attempts to resolve the symbols, and output a trace
  // to the ostream os.  The format for each line of the backtrace is:
  //
  //    <tab>SymbolName[0xAddress+Offset] (FileName:LineNo)
  //
  // This function should only be called if Init() has been called.  We do not
  // LOG(FATAL) here because this code is called might be triggered by a
  // LOG(FATAL) itself.
  void OutputTraceToStream
  (
    const DWORD64* trace,
    int count,
    std::stringstream* os
  )
  {
    char module_name_raw[MAX_PATH];
    const char * module_name_unknown = "[unknown module]";
    const HANDLE process = GetCurrentProcess();

    for (size_t i = 0; (int(i) < count) && os->good(); ++i)
    {
      const DWORD64 frame = trace[i];

      // Code adapted from MSDN example:
      // http://msdn.microsoft.com/en-us/library/ms680578(VS.85).aspx
      char buffer[sizeof(SYMBOL_INFO) + MAX_SYM_NAME * sizeof(TCHAR)];
      memset(buffer, 0, sizeof(buffer));

      // Initialize symbol information retrieval structures.
      DWORD64 sym_displacement = 0;
      PSYMBOL_INFO pSymbol = reinterpret_cast<PSYMBOL_INFO>(&buffer[0]);
      pSymbol->SizeOfStruct = sizeof(SYMBOL_INFO);
      pSymbol->MaxNameLen = MAX_SYM_NAME;
      BOOL has_symbol = SymFromAddr(process, frame,
                                    &sym_displacement, pSymbol);

      // Attempt to retrieve line number information.
      DWORD line_displacement = 0;
      IMAGEHLP_LINE64 line = {};
      line.SizeOfStruct = sizeof(IMAGEHLP_LINE64);
      BOOL has_line = SymGetLineFromAddr64(process, frame,
                                           &line_displacement, &line);

      // Attempt to retrieve the module to whom the symbol belongs to
      DWORD64 module_base = SymGetModuleBase64(process, frame);

      char * module_name;
      if (module_base && 
        GetModuleFileNameA(HINSTANCE(module_base), module_name_raw, MAX_PATH))
      {
        module_name = module_name_raw;
      }
      else
      {
        module_name = const_cast<char*>(module_name_unknown);
      }

      // Output the backtrace line.
      (*os) << "\t"
            << std::hex << std::setw(8) << std::setfill('0');
      if (has_symbol)
      {
        (*os) << pSymbol->Name
              << " [0x" << trace[i] << "+0x" << sym_displacement << "]";
      }
      else
      {
        // If there is no symbol information, add a spacer.
        (*os) << "(No symbol) [0x" << trace[i] << "]";
      }

      (*os) << std::setw(0) << std::setfill(' ') << std::dec;

      if (has_line)
      {
        (*os) << " (" << line.FileName << ":" << line.LineNumber << ")";
      }

      if (module_base)
      {
        (*os) << "\n\t\t module: " << module_name;
      }

      (*os) << "\n";
    }

    SymCleanup(process);
  }

 private:

  SymbolContext() :
      init_error_(ERROR_SUCCESS)
  {
    // Initializes the symbols for the process.
    // Defer symbol load until they're needed, use undecorated names, and
    // get line numbers.
    // This requires that *.pdb files exist in the same folder as the binaries,
    // otherwise they will not work.
    SymSetOptions(SYMOPT_DEFERRED_LOADS |
                  SYMOPT_UNDNAME |
                  SYMOPT_LOAD_LINES);
    if (SymInitialize(GetCurrentProcess(), NULL, TRUE))
    {
      init_error_ = ERROR_SUCCESS;
    }
    else
    {
      init_error_ = GetLastError();
      // TODO(awong): Handle error: SymInitialize can fail with
      // ERROR_INVALID_PARAMETER.
      // When it fails, we should not call debugbreak since it kills the
      // current process (prevents future tests from running or kills the
      // browser process).
      std::cerr << "SymInitialize failed: " << init_error_;
    }
  }

  DWORD init_error_;
};


StackTrace::StackTrace() :
    count_(0)
{
    count_ = CaptureStackBackTrace
    (
        0,
        kMaxTraces,
        reinterpret_cast<PVOID*>(&trace_),
        NULL
    );
}

StackTrace::StackTrace(const PCONTEXT pContext) :
    count_(0)
{
  StackWalkContext(pContext);
}

StackTrace::StackTrace(EXCEPTION_POINTERS* exception_pointers) :
    count_(0)
{
  // When walking an exception stack, we need to use StackWalk64().
  StackWalkContext(exception_pointers->ContextRecord);
}

StackTrace::~StackTrace()
{
}

void StackTrace::StackWalkContext(PCONTEXT contextRecord)
{
  const HANDLE process = GetCurrentProcess();
  const HANDLE thread = GetCurrentThread();

  CONTEXT context_copy;
  memcpy(&context_copy, contextRecord, sizeof(context_copy));
  context_copy.ContextFlags = CONTEXT_INTEGER | CONTEXT_CONTROL;

  // Initialize stack walking.
  STACKFRAME64 stack_frame;
  memset(&stack_frame, 0, sizeof(stack_frame));

#if defined(_WIN64) || defined(WIN64)
  int machine_type = IMAGE_FILE_MACHINE_AMD64;
  stack_frame.AddrPC.Offset = contextRecord->Rip;
  stack_frame.AddrFrame.Offset = contextRecord->Rbp;
  stack_frame.AddrStack.Offset = contextRecord->Rsp;
#else
  int machine_type = IMAGE_FILE_MACHINE_I386;
  stack_frame.AddrPC.Offset = contextRecord->Eip;
  stack_frame.AddrFrame.Offset = contextRecord->Ebp;
  stack_frame.AddrStack.Offset = contextRecord->Esp;
#endif
  stack_frame.AddrPC.Mode = AddrModeFlat;
  stack_frame.AddrFrame.Mode = AddrModeFlat;
  stack_frame.AddrStack.Mode = AddrModeFlat;

  while (StackWalk64(machine_type,
                     process,
                     thread,
                     &stack_frame,
                     &context_copy,
                     NULL,
                     &SymFunctionTableAccess64,
                     &SymGetModuleBase64,
                     NULL) &&
         count_ < kMaxTraces)
  {
    trace_[count_++] = stack_frame.AddrPC.Offset;
  }
}

const DWORD64* StackTrace::Addresses(size_t* count) const
{
  *count = count_;
  if (count_)
    return trace_;
  return NULL;
}

void StackTrace::OutputToStream(std::stringstream* os)
{
  SymbolContext* context = SymbolContext::GetInstance();
  if(context!=NULL)
  {
    DWORD error = context->init_error();
    if (error != ERROR_SUCCESS)
    {
      (*os) << "Error initializing symbols (" << error
            << ").  Dumping unresolved backtrace:\n";
      for (int i = 0; (i < count_) && os->good(); ++i)
      {
        (*os) << "\t" << trace_[i] << "\n";
      }
    }
    else
    {
      (*os) << "\n\nBacktrace:\n";
      context->OutputTraceToStream(trace_, count_, os);
    }

    delete context;
    context=NULL;
  }
}

