module Parsing
  ( block
  ) where

import Control.Monad (void)

import Text.Megaparsec hiding (space)
import Text.Megaparsec.String
import qualified Text.Megaparsec.Expr as Expr
import qualified Text.Megaparsec.Lexer as Lexer

import Ast

space :: Parser ()
space = Lexer.space (void spaceChar)
                    (Lexer.skipLineComment "--")
                    (Lexer.skipBlockCommentNested "{-" "-}")

symbol :: String -> Parser String
symbol = Lexer.symbol $ space

lexeme :: Parser a -> Parser a
lexeme = Lexer.lexeme space

leftParen :: Parser String
leftParen = symbol "(" <?> "left parenthesis"

rightParen :: Parser String
rightParen = symbol ")" <?> "right parenthesis"

literal :: Parser Term
literal = Literal . read <$> (lexeme $ someTill digitChar space)

var :: Parser Term
var = Var <$> lexeme (some letterChar)

functionCall :: Parser Term
functionCall = do
    name <- lexeme $ some letterChar
    leftParen
    vars <- sepEndBy expr $ symbol ","
    rightParen
    let arity = length vars
    let funcCall = FunctionCall name arity
    return $ Call funcCall vars

scope :: Parser Term
scope = Scope <$> block

while :: Parser Term
while = do
  symbol "while" <?> "while"
  t <- term
  b <- block
  return $ while t b

term :: Parser Term
term =
   (try functionCall <?> "function call") <|>
   (try var <?> "variable") <|>
   (scope <?> "scope")
   (while <?> "while loop")
   (literal <?> "literal")

opToString :: Operator -> String
opToString Add = "+"
opToString Sub = "-"
opToString Mul = "*"
opToString Div = "/"

opToFunc :: Operator -> Term -> Term -> Term
opToFunc op = \l r -> Infix l op r

opToElement :: Operator -> Expr.Operator Parser Term
opToElement op = Expr.InfixL $ opToFunc op <$ (symbol $ opToString op)

table = [ [ opToElement Mul
         , opToElement Div ]
       , [ opToElement Add
         , opToElement Sub ] ]

expr :: Parser Term
expr = Expr.makeExprParser term table

semicolon :: Parser String
semicolon = symbol ";" <?> "semicolon"

termSemicolon :: Parser Statement
termSemicolon = do
  t <- expr
  semicolon
  return $ TermSemicolon t

binding :: Parser (String, Term)
binding = do
  var <- lexeme (some letterChar) <?> "variable name"
  symbol "=" <?> "equal sign"
  rhs <- expr
  return (var, rhs)

letBinding :: Parser Statement
letBinding = do
  symbol "let" <?> "let"
  (var, rhs) <- binding
  semicolon
  return $ Let var rhs

letMut :: Parser Statement
letMut = do
  symbol "let" <?> "let"
  symbol "mut" <?> "mut"
  (var, rhs) <- binding
  semicolon
  return $ LetMut var rhs

mutate :: Parser Statement
mutate = do
  (var, rhs) <- binding
  semicolon
  return $ Mutate var rhs

statement :: Parser Statement
statement =
  try letMut <|> try mutate <|> letBinding <|> termSemicolon <?> "statement"

block :: Parser Block
block = do
  symbol "{"
  stmts <- some $ try statement
  -- error . show $ stmts
  end <- expr
  symbol "}"
  return $ Block stmts end

-- TODO:
-- Handle the error properly.
toBlock :: String -> Block
toBlock str = unwrap $ parse block "" str
 where
   unwrap (Left err) = error $ show err
   unwrap (Right term) = term

block :: Block
block = toBlock "{ let mut a = while 0 { foo(b, 1 + 1) }; 6 + 3 * 5 }"

getTree :: IO (Ptr ())
getTree = do
  ptr <- newStablePtr block
  return $ castStablePtrToPtr ptr
foreign export ccall getTree :: IO (Ptr ())