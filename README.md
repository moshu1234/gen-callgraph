gen-callgraph
=============

Copyright (C) 2011-2015 Jerry Chen <mailto:onlyuser@gmail.com>

About:
------

gen-callgraph is a script to generate call graph from elf binary.

A Motivating Example
--------------------

input: elf binary from below source:
<pre>
void A();
void C() {A();}
void B() {C();}
void A() {B(); C();}

int main(int argc, char** argv)
{
    A();
    return 0;
}
</pre>

output: graphviz dot for below graph:

![picture alt](https://sites.google.com/site/onlyuser/files/gen-callgraph.png "gen-callgraph")

Requirements
------------

* bash
* readelf
* objdump
* c++filt
* dot

Limitations
-----------

<ul>
    <li>Only supports statically linked functions within one x86_64 binary.</li>
    <li>Does not detect C++ class constructor/destructor.</li>
    <li>Only tested on small binaries.</li>
</ul>

Installation (Debian):
----------------------

1. git clone https://github.com/onlyuser/gen-callgraph.git

Usage
-----

<pre>
gen-call-graph &lt;BINARY&gt; [DEBUG={0*/1}] | dot -Tpng -ocallgraph.png
</pre>

References
----------

<dl>
    <dt>"Disassemble raw x64 machine code"</dt>
    <dd>http://stackoverflow.com/questions/19071461/disassemble-raw-x64-machine-code</dd>

    <dt>"Graphviz - Graph Visualization Software"</dt>
    <dd>http://www.graphviz.org/</dd>
</dl>

Keywords
--------

    call graph, asm, disassembly, elf, graphviz, name mangling
