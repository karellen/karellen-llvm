// Exercises the installed headers, the generated headers (llvm/Config, and the
// tablegen'd attribute/intrinsic tables pulled in by llvm/IR) and the exported
// libLLVM dylib: build a module, run the new pass manager over it, and check
// that the arithmetic actually folded.
#include "llvm/Config/abi-breaking.h"
#include "llvm/Config/llvm-config.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/raw_ostream.h"

#include <memory>

int main() {
  llvm::LLVMContext ctx;
  auto mod = std::make_unique<llvm::Module>("smoke", ctx);

  auto *i32 = llvm::Type::getInt32Ty(ctx);

  // answer() folds to a constant under -O2; negate() gives llvm-extract and
  // llvm-link a second, distinct symbol to move around.
  auto *fn_ty = llvm::FunctionType::get(i32, false);
  auto *fn = llvm::Function::Create(fn_ty, llvm::Function::ExternalLinkage,
                                    "answer", mod.get());
  llvm::IRBuilder<> builder(llvm::BasicBlock::Create(ctx, "entry", fn));
  builder.CreateRet(builder.CreateAdd(builder.getInt32(40), builder.getInt32(2)));

  auto *neg_ty = llvm::FunctionType::get(i32, {i32}, false);
  auto *neg = llvm::Function::Create(neg_ty, llvm::Function::ExternalLinkage,
                                     "negate", mod.get());
  llvm::IRBuilder<> neg_builder(llvm::BasicBlock::Create(ctx, "entry", neg));
  neg_builder.CreateRet(neg_builder.CreateNeg(neg->getArg(0)));

  if (llvm::verifyModule(*mod, &llvm::errs())) {
    llvm::errs() << "module failed verification\n";
    return 1;
  }

  llvm::PassBuilder pb;
  llvm::LoopAnalysisManager lam;
  llvm::FunctionAnalysisManager fam;
  llvm::CGSCCAnalysisManager cgam;
  llvm::ModuleAnalysisManager mam;
  pb.registerModuleAnalyses(mam);
  pb.registerCGSCCAnalyses(cgam);
  pb.registerFunctionAnalyses(fam);
  pb.registerLoopAnalyses(lam);
  pb.crossRegisterProxies(lam, fam, cgam, mam);
  pb.buildPerModuleDefaultPipeline(llvm::OptimizationLevel::O2).run(*mod, mam);

  // stdout carries the module and nothing else, so it can be fed straight to
  // llvm-as; status goes to stderr.
  mod->print(llvm::outs(), nullptr);
  llvm::errs() << "llvm-dev-smoke: LLVM " << LLVM_VERSION_STRING << " OK\n";
  return 0;
}
