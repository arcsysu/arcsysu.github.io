%{
#include "parser.hh"
#include <llvm/Support/JSON.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/Support/raw_ostream.h>
#define yyerror(x)                                                             \
  do {                                                                         \
    llvm::errs() << (x);                                                       \
  } while (0)

namespace {
auto llvmin = llvm::MemoryBuffer::getFileOrSTDIN("-");
auto input = llvmin.get() -> getBuffer();

auto end = input.end(), it = input.begin();
auto wk_getline(char endline = '\n') {
  auto beg = it;
  while (it != end && *it != endline)
    ++it;
  auto len = it - beg;
  if (it != end && *it == endline)
    ++it;
  return llvm::StringRef(beg, len);
}

llvm::json::Array stak;
} // namespace

auto yylex() {
  auto tk = wk_getline();
  auto b = tk.find("'") + 1, e = tk.rfind("'");
  auto s = tk.substr(b, e - b), t = tk.substr(0, tk.find(" "));
  if (t == "numeric_constant") {
    stak.push_back(
        llvm::json::Object{{"kind", "IntegerLiteral"}, {"value", s}});
    return T_NUMERIC_CONSTANT;
  }
  if (t == "identifier") {
    stak.push_back(llvm::json::Object{{"value", s}});
    return T_IDENTIFIER;
  }
  if (t == "int")
    return T_INT;
  if (t == "return")
    return T_RETURN;
  if (t == "semi")
    return T_SEMI;
  if (t == "l_paren")
    return T_L_PAREN;
  if (t == "r_paren")
    return T_R_PAREN;
  if (t == "l_brace")
    return T_L_BRACE;
  if (t == "r_brace")
    return T_R_BRACE;
  if (t == "equal")
    return T_EQUAL;
  if (t == "greater")
    return T_GREATER;
  if (t == "if")
    return T_IF;
  if (t == "else")
    return T_ELSE;
  return YYEOF;
}

int main() {
  // call yylex() to get successive tokens
  yyparse();
  // output the final parse tree
  llvm::outs() << stak.back() << "\n";
}
%}
%token T_NUMERIC_CONSTANT
%token T_IDENTIFIER
%token T_INT
%token T_RETURN
%token T_SEMI
%token T_L_PAREN
%token T_R_PAREN
%token T_L_BRACE
%token T_R_BRACE
%token T_EQUAL;
%token T_GREATER;
%token T_IF;
%token T_ELSE;
%start CompUnit

%%

CompUnit: xwVarDef FuncDef {
  // global variable + function
  llvm::errs() << " -- CompUnit:xwVarDef FuncDef\n";
  auto inner2 = stak.back();
  stak.pop_back();
  auto inner1 = stak.back();
  stak.pop_back();
  stak.push_back(llvm::json::Object{{"kind", "TranslationUnitDecl"},
                                    {"inner", llvm::json::Array{inner1, inner2}}});
}
| xwVarDef {
  // global variable only
  llvm::errs() << " -- CompUnit:xwVarDef\n";
  auto inner = stak.back();
  stak.pop_back();
  stak.push_back(llvm::json::Object{{"kind", "TranslationUnitDecl"},
                                    {"inner", llvm::json::Array{inner}}});
}
| FuncDef {
  // global function only
  llvm::errs() << " -- CompUnit:FuncDef\n";
  for (auto i = 0; i < stak.size(); i++) llvm::outs() << llvm::formatv("{0:2}", stak[i]) << "\n";
  auto inner = stak.back();
  stak.pop_back();
  stak.push_back(llvm::json::Object{{"kind", "TranslationUnitDecl"},
                                    {"inner", llvm::json::Array{inner}}});
}
| %empty // neither

xwVarDef: T_INT Ident T_SEMI {
  llvm::errs() << " -- VarDecl\n";
  auto name = stak.back().getAsObject();
  assert(name != nullptr);
  assert(name->get("value") != nullptr);
  stak.pop_back();
  stak.push_back(llvm::json::Object{{"kind", "VarDecl"},
                                    {"name", *(name->get("value"))}});
}

FuncDef: T_INT Ident T_L_PAREN T_R_PAREN Block {
  llvm::errs() << " -- FuncDef\n";
  for (auto i = 0; i < stak.size(); i++) llvm::outs() << llvm::formatv("{0:2}", stak[i]) << "\n";
  auto inner = stak.back();
  stak.pop_back();
  auto name = stak.back().getAsObject();
  assert(name != nullptr);
  assert(name->get("value") != nullptr);
  stak.pop_back();
  stak.push_back(llvm::json::Object{{"kind", "FunctionDecl"},
                                    {"name", *(name->get("value"))},
                                    {"inner", llvm::json::Array{inner}}});
}

Ident: T_IDENTIFIER {}

Block: T_L_BRACE T_R_BRACE {}

Block: T_L_BRACE BlockItem T_R_BRACE {}

BlockItem: xwStmt {
  llvm::errs() << " -- BlockItem\n";
  for (auto i = 0; i < stak.size(); i++) llvm::outs() << llvm::formatv("{0:2}", stak[i]) << "\n";
  auto inner = stak.back();
  stak.pop_back();
  stak.push_back(llvm::json::Object{{"kind", "CompoundStmt"},
                                    {"inner", llvm::json::Array{inner}}});
}

BlockItem: BlockItem xwStmt {
  auto inner = stak.back();
  stak.pop_back();
  auto fa = stak.back();
  fa.getAsObject()->get("inner")->getAsArray()->push_back(inner);
  stak.pop_back();
  stak.push_back(fa);
}

xwStmt: xwBinaryOperator
      | xwIfStmt
      | RetStmt

xwBinaryOperator: xwBinaryOperatorExp T_SEMI {
    llvm::errs() << " -- xwBinaryOperatorExp\n";
}

xwBinaryOperatorExp: Ident xwOp Exp {
  auto exp = stak.back();
  stak.pop_back();
  auto ident = stak.back();
  stak.pop_back();
  stak.push_back(llvm::json::Object{{"kind", "BinaryOperator"},
                                    {"inner", llvm::json::Array{ident,exp}}});
}

xwOp: T_EQUAL
    | T_GREATER

xwIfStmt: T_IF T_L_PAREN xwBinaryOperatorExp T_R_PAREN Block T_ELSE Block {
  llvm::errs() << " -- IfStmt\n";
  auto inner3 = stak.back();
  stak.pop_back();
  auto inner2 = stak.back();
  stak.pop_back();
  auto inner1 = stak.back();
  stak.pop_back();
  stak.push_back(llvm::json::Object{{"kind", "IfStmt"},
                         {"inner", llvm::json::Array{inner1, inner2, inner3}}});
}
    | T_IF T_L_PAREN xwBinaryOperatorExp T_R_PAREN Block {}

RetStmt: T_RETURN Exp T_SEMI {
  llvm::errs() << " -- RetStmt\n";
  for (auto i = 0; i < stak.size(); i++) llvm::outs() << llvm::formatv("{0:2}", stak[i]) << "\n";
  auto inner = stak.back();
  stak.pop_back();
  stak.push_back(llvm::json::Object{{"kind", "ReturnStmt"},
                                    {"inner", llvm::json::Array{inner}}});
}

Exp: T_NUMERIC_CONSTANT {}

%%
