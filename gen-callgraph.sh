#!/bin/bash

CMD=`basename $0`

show_help()
{
    echo "Usage: $CMD <BINARY> [DEBUG={0*/1}] | dot -Tpng -ocallgraph.png"
}

if [ $# -ne 1 -a $# -ne 2 ]; then
    echo "Fail! -- Expecting 1 or 2 arguments! ==> $@"
    show_help
    exit 1
fi

if [ -z "`which readelf`" ]; then
    echo "Error: Requires \"readelf\""
    exit 1
fi

if [ -z "`which objdump`" ]; then
    echo "Error: Requires \"objdump\""
    exit 1
fi

if [ -z "`which c++filt`" ]; then
    echo "Error: Requires \"c++filt\""
    exit 1
fi

if [ -z "`which dot`" ]; then
    echo "Error: Requires \"dot\""
    exit 1
fi

EXEC=$1
DEBUG=$2

if [ ! -f "$EXEC" ]; then
    echo "Error: $EXEC doesn't exist!"
    exit 1
fi

if [ -z "$DEBUG" ]; then
    DEBUG=0
fi

#readelf $EXEC --all
GEN_SYM_FILE_CMD="readelf $EXEC --headers --symbols"

#http://stackoverflow.com/questions/1737095/how-do-i-disassemble-raw-x86-code
#http://stackoverflow.com/questions/19071461/disassemble-raw-x64-machine-code

#objdump -D -b binary -mi386 -Maddr16,data16 $EXEC
GEN_ASM_FILE_CMD="objdump -D -b binary -mi386:x86-64 $EXEC"

if [ "$DEBUG" == 1 ]; then
    echo "readelf command: $GEN_SYM_FILE_CMD"
    echo "objdump command: $GEN_ASM_FILE_CMD"
    echo ""
fi

SYM_FILE_CONTENTS="`$GEN_SYM_FILE_CMD`"
ASM_FILE_CONTENTS="`$GEN_ASM_FILE_CMD`"

if [ "$DEBUG" == 1 ]; then
    DEBUG_SYM_FILE="`mktemp`"
    DEBUG_ASM_FILE="`mktemp`"
    #trap "rm $DEBUG_SYM_FILE $DEBUG_ASM_FILE" EXIT
    echo "$SYM_FILE_CONTENTS" > $DEBUG_SYM_FILE
    echo "$ASM_FILE_CONTENTS" > $DEBUG_ASM_FILE
    echo "Cached readelf output: $DEBUG_SYM_FILE"
    echo "Cached objdump output: $DEBUG_ASM_FILE"
    echo ""
fi

ENTRY_POINT_LINE="`echo \"$SYM_FILE_CONTENTS\" | grep \"Entry point address:\"`"
ENTRY_POINT_ADDR="`echo \"$ENTRY_POINT_LINE\" | cut -d':' -f2 | tr -d ' ' | sed 's/^0x400//g'`"

FUNC_TRIPLE_LIST=""
FOUND_SYMTAB=0
while read SYM_FILE_LINE; do
    if [ "$FOUND_SYMTAB" == 0 ]; then
        if [[ "$SYM_FILE_LINE" =~ "Symbol table '.symtab'" ]]; then
            FOUND_SYMTAB=1
        else
            continue
        fi
    fi
    SYM_TUPLE="`echo \"$SYM_FILE_LINE\" | sed 's/[ ]\+/ /g'`"
    if [ "`echo \"$SYM_TUPLE\" | cut -d' ' -f4`" == "FUNC" ] &&
       [ "`echo \"$SYM_TUPLE\" | cut -d' ' -f5`" == "GLOBAL" ] &&
       [ "`echo \"$SYM_TUPLE\" | cut -d' ' -f7`" != "UND" ];
    then
        FUNC_PAIR="`echo \"$SYM_TUPLE\" | cut -d' ' -f2,8 | sed 's/^0000000000400//g'`"
        FUNC_ADDR="`echo \"$FUNC_PAIR\" | cut -d' ' -f1`"
        FUNC_ADDR_DEC="`printf \"%d\" 0x$FUNC_ADDR`"
        FUNC_TRIPLE="$FUNC_ADDR_DEC $FUNC_PAIR"
        FUNC_TRIPLE_LIST="$FUNC_TRIPLE_LIST\n$FUNC_TRIPLE"
    fi
done <<< "$SYM_FILE_CONTENTS"
if [ "$FOUND_SYMTAB" == 0 ]; then
    echo "Error: Can't find symtab section in \"$EXEC\"."
    exit
fi
SORTED_FUNC_PAIR_LIST="`echo -e \"$FUNC_TRIPLE_LIST\" | sort | grep -v '^$' | cut -d' ' -f2,3`"

echo "digraph `basename $EXEC` {"
echo "rankdir=LR;"
echo "node [shape=ellipse];"

while read -r FUNC_PAIR; do
    FUNC_ADDR="`echo \"$FUNC_PAIR\" | cut -d' ' -f1`"
    FUNC_NAME="`echo \"$FUNC_PAIR\" | cut -d' ' -f2`"
    FUNC_NAME_DEMANGLED="`echo $FUNC_NAME | c++filt`"
    if [ "$FUNC_ADDR" == "$ENTRY_POINT_ADDR" ]; then
        SHAPE_SPEC_STR=", shape=\"box\""
    else
        SHAPE_SPEC_STR=""
    fi
    echo "$FUNC_NAME [label=\"0x$FUNC_ADDR: $FUNC_NAME_DEMANGLED\"$SHAPE_SPEC_STR];"
done <<< "$SORTED_FUNC_PAIR_LIST"

i=1
while read -r FUNC_PAIR; do
    FUNC_ADDR="`echo \"$FUNC_PAIR\" | cut -d' ' -f1`"
    FUNC_NAME="`echo \"$FUNC_PAIR\" | cut -d' ' -f2`"

    FUNC_ASM_LINE_NO="`echo \"$ASM_FILE_CONTENTS\" | grep -n \"^[ ]*$FUNC_ADDR:\" | head -1 | cut -d':' -f1`"
    if [ -z "$FUNC_ASM_LINE_NO" ]; then
        i="`expr $i + 1`"
        continue
    fi

    NEXT_FUNC_INDEX="`expr $i + 1`"
    NEXT_FUNC_PAIR="`echo \"$SORTED_FUNC_PAIR_LIST\" | head -$NEXT_FUNC_INDEX | tail -1`"

    NEXT_FUNC_ADDR="`echo \"$NEXT_FUNC_PAIR\" | cut -d' ' -f1`"
    if [ -z "$NEXT_FUNC_ADDR" ]; then
        i="`expr $i + 1`"
        continue
    fi
    NEXT_FUNC_NAME="`echo \"$NEXT_FUNC_PAIR\" | cut -d' ' -f2`"

    NEXT_FUNC_ASM_LINE_NO="`echo \"$ASM_FILE_CONTENTS\" | grep -n \"^[ ]*$NEXT_FUNC_ADDR:\" | head -1 | cut -d':' -f1`"
    FUNC_ASM_LAST_LINE_NO="`expr $NEXT_FUNC_ASM_LINE_NO - 1`"
    FUNC_ASM_BODY_LEN="`expr $NEXT_FUNC_ASM_LINE_NO - $FUNC_ASM_LINE_NO`"
    FUNC_ASM_BODY="`echo \"$ASM_FILE_CONTENTS\" | head -$FUNC_ASM_LAST_LINE_NO | tail -$FUNC_ASM_BODY_LEN`"
    CALLEE_ASM_LINES_LIST="`echo \"$FUNC_ASM_BODY\" | grep 'callq'`"
    if [ -z "$CALLEE_ASM_LINES_LIST" ]; then
        i="`expr $i + 1`"
        continue
    fi

    while read -r CALLEE_ASM_LINE; do
        CALLEE_ADDR_PART="`echo \"$CALLEE_ASM_LINE\" | cut -d'	' -f1`"
        CALL_ADDR="`echo \"$CALLEE_ADDR_PART\" | cut -d':' -f1`"
        CALLEE_CMD="`echo \"$CALLEE_ASM_LINE\" | cut -d'	' -f3`"
        CALLEE_ADDR="`echo \"$CALLEE_CMD\" | sed 's/callq[ ]\+0x\([^ ]\+\)/\1/g'`"
        CALLEE_NAME="`echo \"$SORTED_FUNC_PAIR_LIST\" | grep \"$CALLEE_ADDR\" | cut -d' ' -f2`"
        if [ -z "$CALLEE_NAME" ]; then
            continue
        fi
        echo "$FUNC_NAME -> $CALLEE_NAME [label=\"0x$CALL_ADDR\"]"
    done <<< "$CALLEE_ASM_LINES_LIST"

    i="`expr $i + 1`"
done <<< "$SORTED_FUNC_PAIR_LIST"

echo "}"
