#!/usr/bin/tclsh

set comments 1
set target_line_length 60
set indent "  "

set preamble "/*\n * DO NOT EDIT !!\n *\n * The files:\n *\tinkpot_define.h\n *\tinkpot_value_table.h\n *\tinkpot_scheme_table.h\n * are generated as a matched set.\n */\n"

if {! $argc} {exit}

source inkpot_lib_procs.tcl

#------------------------------------------------- set_up
# merge input data
foreach {lib} $argv {
    set f [open $lib r]
    array set COLORS [read $f [file size $lib]]
    close $f

    foreach {scheme coding} $COLORS() {break}
    array unset COLORS {}
    lappend ALL_STRINGS($scheme) scheme
    set ALL_SCHEMES($scheme) {}

    foreach {color} [array names COLORS] {
        set value $COLORS($color)

	# if a named color ends in a number, convert it to an indexed color
        if {[llength $color] == 1
        && [regexp -- {([a-z]+)([0-9]+)} $color . icolor index] == 1} {
            unset COLORS($color)
            set color [list $icolor $index]
            set COLORS($color) $value
        }

        switch [llength $color] {
            1 {
                lappend ALL_STRINGS($color) color
		map CV $color $value $scheme
            }
            2 {
                foreach {icolor index} $color {break}
                lappend ALL_STRINGS($icolor) icolor
		map ICRIV $icolor [list 0 $index $value] $scheme
            }
            3 {
                foreach {icolor range index} $color {break}
                lappend ALL_STRINGS($icolor) icolor
		map ICRIV $icolor [list $range $index $value] $scheme
            }
            default {
                puts stderr "wrong number of keys in: \"$color\""
            }
        }
    }
}

#------------------------------------------------- write inkpot_value_table.h
set f [open inkpot_value_table.h w]
puts $f $preamble

# generate TAB_VALUES_24
set SZT_VALUES 0
tab_begin $f "unsigned char TAB_VALUES_24\[SZT_VALUES_24\] = {"
foreach {value} [map2 CV] {
    tab_begin_block $f $SZT_VALUES

    foreach {r g b} $value {break}
    tab_elem $f [format "0x%02x,0x%02x,0x%02x," $r $g $b]

    set ALL_VALUES_coded($value) $SZT_VALUES
    incr SZT_VALUES
    
    # comment shows {{color {scheme...}}...}
    tab_end_block $f [map2m1 CV $value]
}
tab_end $f "};\n"


# generate NONAME_VALUES_24
set SZT_NONAME_VALUES 0
tab_begin $f "unsigned char TAB_NONAME_VALUES_24\[SZT_NONAME_VALUES_24\] = {"
foreach {range_index_value} [lsort -dictionary [map2 ICRIV]] {
    foreach {range index value} $range_index_value {break}
    if {! [info exists ALL_VALUES_coded($value)]} {
        tab_begin_block $f $SZT_NONAME_VALUES
    
        foreach {r g b} $value {break}
        tab_elem $f [format "0x%02x,0x%02x,0x%02x," $r $g $b]

        set ALL_VALUES_coded($value) [expr $SZT_NONAME_VALUES + $SZT_VALUES]
        incr SZT_NONAME_VALUES

        # comment shows {{icolor {scheme...}}...}
    	tab_end_block $f [map2m1 ICRIV $range_index_value]
    }
}
tab_end $f "};\n"
    
close $f
#------------------------------------------------- write inkpot_scheme_table.h
set f [open inkpot_scheme_table.h w]
puts $f $preamble

# generate TAB_STRINGS
set SZT_STRINGS 0
set SZL_STRINGS 0
set SZW_STRINGS 0
tab_begin $f "const char TAB_STRINGS\[SZT_STRINGS\] = {"
foreach {string} [lsort -ascii [array names ALL_STRINGS]] {
    tab_begin_block $f $SZT_STRINGS
    
    tab_elem $f "\"$string\\0\""

    set len [string length $string]
    # include the null
    incr len

    tab_end_block $f $len
    
    foreach {usage} $ALL_STRINGS($string) {
        switch $usage {
            scheme {
                set ALL_SCHEME_STRINGS_coded($string) $SZT_STRINGS
            }
            icolor {
                set ALL_ICOLOR_STRINGS_coded($string) $SZT_STRINGS
            }
            color {
                set ALL_COLOR_STRINGS_coded($string) $SZT_STRINGS
            }
            default {
                puts stderr "Unknown usage $usage for string \"$string\""
            }
        }
    }
    incr SZW_STRINGS
    if {$len > $SZL_STRINGS} {set SZL_STRINGS $len}
    incr SZT_STRINGS $len
}
tab_end $f "};\n"
# don't count the null in the length of the longest string
incr SZL_STRINGS -1


foreach {m2} [lsort -dictionary [mapm2 ICRIV]] {
    foreach {RIV schemes} $m2 {break}
    foreach {range index value} $RIV {break}
    foreach {m1} [map2m1 ICRIV $RIV] {
	 foreach {icolor schemes} $m1 {break}
	 lappend ALL_RANGES([list $icolor $range $schemes]) $m2
    }
}

# generate TAB_INDEXES
set SZT_INDEXES 0
set index -1
tab_begin $f "IDX_VALUES TAB_INDEXES\[SZT_INDEXES\] = {"
foreach {icolor_range_schemes} [lsort -ascii [array names ALL_RANGES]] {
    tab_begin_block $f $SZT_INDEXES
    foreach {m2} $ALL_RANGES($icolor_range_schemes) {
	foreach {RIV schemes} $m2 {break}
	foreach {range index value} $RIV {break}
        tab_elem $f $ALL_VALUES_coded($value),
        incr SZT_INDEXES
    }
    set size [llength $ALL_RANGES($icolor_range_schemes)]
    set ALL_RANGES_coded($icolor_range_schemes) [list $SZT_INDEXES $size]
    tab_end_block $f "[map2m1 ICRIV $RIV] $size"
}
tab_end $f "};\n"

# generate TAB_RANGES
set SZT_RANGES 0
set last_icolor ""
tab_begin $f "inkpot_range_t TAB_RANGES\[SZT_RANGES\] = {"
foreach {icolor_range_schemes} [lsort -dictionary [array names ALL_RANGES_coded]] {
    foreach {icolor range schemes} $icolor_range_schemes {break}
    foreach {first_idx size} $ALL_RANGES_coded($icolor_range_schemes) {break}
    if {! [string equal $last_icolor $icolor]} {
	 if {! [string equal $last_icolor ""]} {
	     tab_end_block $f [list $icolor $schemes $cnt]
         }
         tab_begin_block $f $SZT_RANGES
	 set cnt 0
	 set last_icolor $icolor
    }
    set size [llength $ALL_RANGES($icolor_range_schemes)]
    tab_elem $f "{$size,$first_idx},"
    incr SZT_RANGES
    incr cnt
}
tab_end_block $f [list $icolor $schemes $cnt]
tab_end $f "};\n"


# generate TAB_ICOLORS
set SZT_ICOLORS 0
set last_icolor ""
tab_begin $f "inkpot_scheme_index_t TAB_ICOLORS\[SZT_ICOLORS\] = {"
foreach {icolor_range_schemes} [lsort -dictionary [array names ALL_RANGES_coded]] {
    foreach {icolor range schemes} $icolor_range_schemes {break}
    foreach {first_idx size} $ALL_RANGES_coded($icolor_range_schemes) {break}
    if {! [string equal $last_icolor $icolor]} {
	 if {! [string equal $last_icolor ""]} {tab_end_block $f [list $icolor $schemes]}
         tab_begin_block $f $SZT_ICOLORS
	 tab_elem $f "{$ALL_ICOLOR_STRINGS_coded($icolor),$first_idx},"
	 set  last_icolor $icolor
    }
    set ALL_ICOLORS_coded($color) $SZT_ICOLORS
    incr SZT_ICOLORS
}
tab_end_block $f [list $icolor $schemes]
tab_end $f "};\n"
		    

# generate TAB_SCHEMES
set SZT_SCHEMES 0
tab_begin $f "inkpot_scheme_name_t TAB_SCHEMES\[SZT_SCHEMES\] = {"
foreach {scheme} [lsort -ascii [array names ALL_SCHEMES]] {
    tab_begin_block $f $SZT_SCHEMES
    
#    tab_elem $f "{$ALL_SCHEME_STRINGS_coded($scheme),$ALL_INDEX_SCHEMES_coded($scheme)},"
    tab_elem $f "{$ALL_SCHEME_STRINGS_coded($scheme)},"
    
    tab_end_block $f $scheme
    
    set ALL_SCHEMES_coded($scheme) [list $SZT_SCHEMES [expr 1 << $SZT_SCHEMES]]
    incr SZT_SCHEMES
}
tab_end $f "};\n"


if {0} {
foreach {m2} [lsort -dictionary [mapm2 CV]] {
    foreach {value schemes} $m2 {break}
    foreach {m1} [map2m1 CV $value] {
        lappend ALL_ALIASES(m1) $m2
    }
}
}


# generate TAB_ALTS
set SZT_ALTS 0
tab_begin $f "inkpot_name_t TAB_ALTS\[SZT_ALTS\] = {"
#foreach {m1} [lsort -ascii [array names ALL_ALIASES]] {
#    foreach {color schemes} $m1 {break}
foreach {r_set} [map3 CV] {
    set scheme_bits 0
    foreach {scheme} $schemes {
        foreach {scheme_idx scheme_bit} $ALL_SCHEMES_coded($scheme) {break}
        set scheme_bits [expr $scheme_bits | $scheme_bit]
    }
    set isneeded 0
    set m2s [map3m2 CV $r_set]
#    set m2s $ALL_ALIASES($m1)
    set cnt [llength $m2s]
    switch $cnt {
        0 {
            puts stderr "shouldn't happen - zero alts: $color"
        }
        1 {
	    foreach {m2} $m2s {break}
            foreach {value schemeset} $m2 {break}
            set ALL_ALTSETS_coded($color) "$ALL_VALUES_coded($value),[format {0x%x} $scheme_bits]"
            # don't need entry in TAB_ALTS for this case
        }
        default {
            set first_idx $SZT_ALTS
	    foreach {m2} $m2s {
	        foreach {value schemeset} $m2 {break}
                tab_begin_block $f $first_idx
                incr isneeded
                tab_elem $f "{[incr cnt -1],$ALL_VALUES_coded($value),[format {0x%x} $scheme_bits]},"
                incr SZT_ALTS
	        set aliases [mapm21 CV $m2]
    	        foreach {color} $aliases {
                    set ALL_ALTSETS_coded($color) "$first_idx,0"
                }
    	    }
        }
    }
    if {$isneeded} {tab_end_block $f $aliases}
#}
tab_end $f "};\n"

    
# generate TAB_NAMES
set SZT_NAMES 0
tab_begin $f "inkpot_name_t TAB_NAMES\[SZT_NAMES\] = {"
foreach {color} [map1 CV] {
    tab_begin_block $f $SZT_NAMES
    
    tab_elem $f "{$ALL_COLOR_STRINGS_coded($color),$ALL_ALTSETS_coded($color)},"
    
    tab_end_block $f $color
    
    set ALL_NAMES_coded($color) $SZT_NAMES
    incr SZT_NAMES
}
tab_end $f "};\n"
    

# generate TAB_TO_NAMES
set SZT_TO_NAMES 0
tab_begin $f "IDX_NAMES TAB_TO_NAMES\[SZT_TO_NAMES\] = {"
foreach {m2} [mapm2 CV] {
    set alias_set [mapm21 CV $m2]
    tab_begin_block $f $SZT_TO_NAMES
    foreach {value schemeset} $m2 {break}
    set ALL_TO_NAMES_coded($value) $SZT_TO_NAMES
    switch [llength $alias_set] {
        0 {
            puts stderr "shouldn't happen - zero maps: $value"
        }
	default {
            set first_idx $SZT_TO_NAMES
	    foreach {color} $alias_set {
        	tab_elem $f $ALL_NAMES_coded($color),
        	lappend comment $color
        	incr SZT_TO_NAMES
    	    }
        }
    }
    if {$isneeded} {tab_end_block $f $alias_set}
}
tab_end $f "};\n"


# generate TAB_VALUE_TO
set SZT_VALUE_TO 0
tab_begin $f "IDX_TO_NAMES TAB_VALUE_TO\[SZT_VALUE_TO\] = {"
# NB - this sort order must match TAB_VALUES
foreach {value} [map2 CV] {
    tab_begin_block $f $SZT_VALUE_TO

    tab_elem $f $ALL_TO_NAMES_coded($value),
    
    tab_end_block $f $ALL_TO_NAMES_coded($value)
    incr SZT_VALUE_TO
}
tab_end $f "};\n"
    
close $f


#------------------------------------------------- write inkpot_define.h
set f [open inkpot_define.h w]
puts $f $preamble

set SZT_VALUES_24 [expr 3*$SZT_VALUES]
set SZT_NONAME_VALUES_24 [expr 3*$SZT_NONAME_VALUES]
incr SZT_VALUES $SZT_NONAME_VALUES

puts $f "\#define SZL_STRINGS $SZL_STRINGS"
puts $f "\#define SZW_STRINGS $SZW_STRINGS"
puts $f ""
foreach {i} {
    STRINGS SCHEMES NAMES ALTS VALUES VALUE_TO TO_NAMES
    ICOLORS INDEXES RANGES NONAME_VALUES
    VALUES_24 NONAME_VALUES_24
} {
    if {[set SZT_$i] < 256} {
        set int "unsigned char"
    } elseif {[set SZT_$i] < 65536} {
        set int "unsigned short"
    } elseif {[set SZT_$i] < 65536*65536} {
        set int "unsigned int"
    } else {
        set int "unsigned long"
    }
    puts $f "\#define SZT_$i [set SZT_$i]"
    puts $f "typedef $int IDX_$i\;"
    puts $f ""
}
foreach {i} {SCHEMES} {
    if {[set SZT_$i] < 8} {
        set int "unsigned char"
    } elseif {[set SZT_$i] < 16} {
        set int "unsigned short"
    } elseif {[set SZT_$i] < 32} {
        set int "unsigned int"
    } elseif {[set SZT_$i] < 64} {
        set int "unsigned long"
    } else {
        puts stderr "more that 64 bits in MSK_$i"
    }
    puts $f "typedef $int MSK_$i\;"
    puts $f ""
}
close $f
