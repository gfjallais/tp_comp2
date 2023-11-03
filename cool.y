/*
 *  cool.y
 *              Parser definition for the COOL language.
 *
 */
%{
#include "cool-io.h"		//includes iostream
#include "cool-tree.h"
#include "stringtab.h"
#include "utilities.h"

/* Locations */
#define YYLTYPE int		   /* the type of locations */
#define cool_yylloc curr_lineno	   /* use the curr_lineno from the lexer
				      for the location of tokens */
extern int node_lineno;		   /* set before constructing a tree node
				      to whatever you want the line number
				      for the tree node to be */

/* The default actions for lacations. Use the location of the first
   terminal/non-terminal and set the node_lineno to that value. */
#define YYLLOC_DEFAULT(Current, Rhs, N)		\
  Current = Rhs[1];				\
  node_lineno = Current;

#define SET_NODELOC (Current)	\
  node_lineno = Current;

extern char *curr_filename;

void yyerror(char *s);        /*  defined below; called for each parse error */
extern int yylex();           /*  the entry point to the lexer  */

/************************************************************************/
/*                DONT CHANGE ANYTHING IN THIS SECTION                  */

Program ast_root;	      /* the result of the parse  */
Classes parse_results;        /* for use in semantic analysis */
int omerrs = 0;               /* number of errors in lexing and parsing */
%}

/* A union of all the types that can be the result of parsing actions. */
%union {
  Boolean boolean;
  Symbol symbol;
  Program program;
  Class_ class_;
  Classes classes;
  Feature feature;
  Features features;
  Formal formal;
  Formals formals;
  Case case_;
  Cases cases;
  Expression expression;
  Expressions expressions;
  char *error_msg;
}

/* 
   Declare the terminals; a few have types for associated lexemes.
   The token ERROR is never used in the parser; thus, it is a parse
   error when the lexer returns it.

   The integer following token declaration is the numeric constant used
   to represent that token internally.  Typically, Bison generates these
   on its own, but we give explicit numbers to prevent version parity
   problems (bison 1.25 and earlier start at 258, later versions -- at
   257)
*/
%token CLASS 258 ELSE 259 FI 260 IF 261 IN 262 
%token INHERITS 263 LET 264 LOOP 265 POOL 266 THEN 267 WHILE 268
%token CASE 269 ESAC 270 OF 271 DARROW 272 NEW 273 ISVOID 274
%token <symbol>  STR_CONST 275 INT_CONST 276 
%token <boolean> BOOL_CONST 277
%token <symbol>  TYPEID 278 OBJECTID 279 
%token ASSIGN 280 NOT 281 LE 282 ERROR 283

/*  DON'T CHANGE ANYTHING ABOVE THIS LINE, OR YOUR PARSER WONT WORK       */
/**************************************************************************/
 
   /* Complete the nonterminal list below, giving a type for the semantic
      value of each non terminal. (See section 3.6 in the bison 
      documentation for details). */

/* Declare types for the grammar's non-terminals. */
%type <program> program
%type <classes> class_list
%type <class_> class

/* You will want to change the following line. */
%type <features> features_list
%type <feature> feature
%type <boolean> boolean
%type <symbol> symbol
%type <formal> formal 
%type <formals> formal_list 
%type <case_> case 
%type <cases> case_list
%type <expressions> expression_list1
%type <expressions> expression_list2
%type <expression> expression
%type <expression> let
%type <expression> optional_assign

/* Precedence declarations go here. */
%left '.'
%left '@'
%left '~' 
%left ISVOID
%left '*' '/'
%left '+' '-'
%nonassoc '<' '=' LE
%right NOT
%right ASSIGN
%right FLAG

%%
/* 
   Save the root of the abstract syntax tree in a global variable.
*/
program	: class_list	{ /* make sure bison computes location information */
			  @$ = @1;
			  ast_root = program($1); }
        ;

class_list
	: class			/* single class */
		{ $$ = single_Classes($1);
                  parse_results = $$; }
	| class_list class	/* several classes */
		{ $$ = append_Classes($1,single_Classes($2)); 
                  parse_results = $$; }
	;

/* If no parent is specified, the class inherits from the Object class. */
class	: CLASS TYPEID '{' features_list '}' ';'
		{ $$ = class_($2,idtable.add_string("Object"),$4,
			      stringtable.add_string(curr_filename)); }
	| CLASS TYPEID INHERITS TYPEID '{' features_list '}' ';'
		{ $$ = class_($2,$4,$6,stringtable.add_string(curr_filename)); }
	;

/* Feature list may be empty, but no empty features in list. */
features_list: 
    {
      $$ = nil_Features();
    }
    | features_list feature { 
      $$ = append_Features($1,single_Features($2));
    };

feature: 
  OBJECTID '(' formal_list ')' ':' TYPEID '{' expression '}' ';' {
      $$ = method($1, $3, $6, $8);
  }
  | OBJECTID ':' TYPEID optional_assign ';' {
      $$ = attr($1, $3, $4)
  }
  | error ';' {};

formal_list:
  {
    $$ = nil_Formals();
  }
  | formal {
    $$ = single_Formals($1)
  }
  | formal_list ',' formal { 
    $$ = append_Formals($1,single_Formals($3));
  };

formal: 
  OBJECTID ':' TYPEID {
    $$ = formal($1, $3);
  }

expression_list1:
  {
    $$ = nil_Expressions();
  }
  | expression {
    $$ = single_Expressions($1);
  } 
  | expression_list1 ',' expression {
    $$ = append_Expressions($1, single_Expressions($3));
  };

expression_list2:
  expression ';' {
    $$ = single_Expressions($1);
  }
  | expression_list2 expression ';' {
    $$ = append_Expressions($1, single_Expressions($2));
  }
  | error ';' { yyerrok; };

optional_assign: 
  {
    $$ = no_expr();
  }
  | ASSIGN expression {
    $$ = $2;
  };

let: 
  OBJECTID ':' TYPEID optional_assign IN expression %prec FLAG {
    $$ = let($1, $3, $4, $6);
  }
  | OBJECTID ':' TYPEID optional_assign ',' let {
    $$ = let($1, $3, $4, $6);
  }
  | error IN expression %prec FLAG { yyerrok; }
  | error ',' let { yyerrok; };

case_list:
  case {
    $$ = single_Cases($1);
  }
  | case_list case {
    $$ = append_Cases($1, single_Cases($2));
  };

case:
  OBJECTID ':' TYPEID DARROW expression ';' {
    $$ = branch($1, $3, $5);
  };

expression: 
  OBJECTID ASSIGN expression {
    $$ = assign($1, $3);
  }
  | expression '@' TYPEID '.' OBJECTID '(' expression_list1 ')' {
    $$ = static_dispatch($1, $3, $5, $7);
  }
  | OBJECTID '(' expression_list1 ')' {
    $$ = dispatch(object(idtable.add_string("self")), $1, $3);
  }
  | IF expression THEN expression ELSE expression FI {
    $$ = cond($2, $4, $6);
  }
  | WHILE expression LOOP expression POOL {
    $$ = loop($2, $4);
  }
  | '{' expression_list2 '}' {
    $$ = block($2);
  }
  | LET let {
    $$ = $2;
  }
  | CASE expression OF case_list ESAC {
    $$ = typcase($2, $4);
  }
  | NEW TYPEID {
    $$ = new_($2);
  }
  | ISVOID expression {
    $$ = isvoid($2);
  }
  | expression '+' expression {
    $$ = plus($1, $3);
  }
  | expression '-' expression {
    $$ = sub($1, $3);
  }
  | expression '*' expression {
    $$ = mul($1, $3);
  }
  | expression '/' expression {
    $$ = divide($1, $3);
  }
  | '~' expression {
    $$ = neg($2);
  }
  | expression '<' expression {
    $$ = lt($1, $3);
  }
  | expression LE expression {
    $$ = leq($1, $3);
  }
  | expression '=' expression {
    $$ = eq($1, $3);
  }
  | NOT expression {
    $$ = comp($2);
  }
  | '(' expression ')' {
    $$ = $2;
  }
  | OBJECTID {
    $$ = object($1);
  }
  | INT_CONST {
    $$ = comp($2);
  }
  | STR_CONST {
    $$ = string_const($1);
  } 
  | BOOL_CONST {
    $$ = bool_const($1);
  } 

/* end of grammar */
%%

/* This function is called automatically when Bison detects a parse error. */
void yyerror(char *s)
{
  extern int curr_lineno;

  cerr << "\"" << curr_filename << "\", line " << curr_lineno << ": " \
    << s << " at or near ";
  print_cool_token(yychar);
  cerr << endl;
  omerrs++;

  if(omerrs>50) {fprintf(stdout, "More than 50 errors\n"); exit(1);}
}

