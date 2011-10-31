
 source $cfgdir/starbase.tcl

 proc iDoc { method args } {
    switch -exact -- $method {
     title {
	set docid [regsub {\..*$} [file tail [lindex $args 0]] {}] 

	if { ![info exists ::iDoc] } {
	    starbase_read iDoc /data/mmti/idoc-db/iDoc.db
	    starbase_foreachrow iDoc -colvars {
		if { ![info exists ::DocTitle($DocID)] } {
		    set ::DocTitle($DocID) $Title
		}
	    }
	}
	if { [info exists ::DocTitle($docid)] && $::DocTitle($docid) ne "" } {
	    return $::DocTitle($docid)
	} else {
	    return [file root [file tail [string map { + { } _ { } - { } } [lindex $args 0]]]]
	}
     }
    }
 }

 proc dict-lappend { dict args } {
    upvar $dict D

    set keys  [lrange $args 0 end-1]
    set value [lindex $args end]

    if { [info exists D] && [dict exists $D {*}$keys] } {
	dict set D {*}$keys [list {*}[dict get $D {*}$keys] $value]
    } else {
	dict set D {*}$keys [list $value]
    }
 }

 proc nop {} {}
 proc format-row { tag rank mtime fsize url file title snip } {
    switch $tag {
     Pages {
	set page [string map { /data/mmti/paige/page/ {} } $file]

        dict set ::Pages $page Page [list $rank $mtime $fsize $url $file $title $snip]
	if { [dict exists $::Pages $page Rank] } {
	    dict set ::Pages $page Rank [expr [dict get $::Pages $page Rank] + $rank]
	} else {
	    dict set ::Pages $page Rank $rank
	}
     }
     Files {
	set file [string map { /data/mmti/paige/file/ {} } $file]
	set page [file dirname $file]
	set file [file tail $file]

        dict-lappend ::Pages $page File [list $rank $mtime $fsize $url $file $title $snip]

	if { [dict exists $::Pages $page Rank] } {
	    dict set ::Pages $page Rank [expr [dict get $::Pages $page Rank] + $rank]
	} else {
	    dict set ::Pages $page Rank $rank
	}
     }
     iDoc  {
	set file [string map { /data/mmti/idoc-db-docs/ {} } $file]
	
        lappend ::iDocs [list $rank $mtime $fsize $url $file $title $snip]
     }
    }

    nop
 }
 proc format-page { pathmap } {

    if { ![info exists ::Pages] } {
	append reply "<h2> No Wiki pages matched </h2>"
    } else {
	append reply "<h2> Wiki pages matched </h2>"
	append reply "<ul>\n"

	foreach page [dict keys $::Pages] {
	    lappend pages $page [dict get $::Pages $page Rank]
	}
	set pages [lsort -decreasing -real -stride 2 -index 1 $pages]


	foreach { page rank } $pages {
	    if { [dict exists $::Pages $page Page] } {
		foreach { rank mtime fsize url file title snip } [dict get $::Pages $page Page] {}

		append reply "<li><a href=\"$url\">$title</a>
		    <small>[string map { { } {&nbsp;} } [clock format $mtime -format "%b %d %Y %T"]]</small>
		    <small>[expr $fsize/1000]K</small>
		    <small><br>[string map { \n " " \f "" } $snip]</small>
		  </li>\n"
	    } else {
		append reply "<li><a href=\"/wiki/mmti/$page\">[string map { + " " _ " " } $page]</a></li>\n"
	    }

	    if { [dict exists $::Pages $page File] } {
		append reply "<ul>\n"
		set files [lsort -decreasing -real -index 0 [dict get $::Pages $page File]]

		foreach file [dict get $::Pages $page File] {
		    foreach { rank mtime fsize url file title snip } $file {}

		    append reply "<li><a href=\"$url\">$title</a>
			    <small>[string map { { } {&nbsp;} } [clock format $mtime -format "%b %d %Y %T"]]</small>
			    <small>[expr $fsize/1000]K</small>
			    <small><br>[string map { \n " " \f "" } $snip]</small>
			</li>\n"
		}

		append reply "</ul>\n"
	    }
	}

	append reply "</ul>\n"
    }

    if { [info exists ::iDocs] } {

	starbase_read iDoc /data/mmti/idoc-db/iDoc.db
	starbase_foreachrow iDoc -colvars {
	    set DocTitle($DocID) $Title
	    if { $Deleted } { set DocDelet($DocID) 1 }
	}

	append reply "<h2>iDoc Database matches</h2><ul>"

	foreach doc $::iDocs {

	    foreach { rank mtime fsize url file title snip } $doc {}

	    set docid [regsub {\..*$} $file {}]

	    if { [info exists DocDone($docid)]  } { continue }
	    if { [info exists DocDelet($docid)] } { continue }
	    if { [info exists DocTitle($docid)] } { set file $DocTitle($docid) }


	    append reply "<li><a href=\"$url\">$docid [string map { + " " _ " " } $file]</a>
		<small>[string map { { } {&nbsp;} } [clock format $mtime -format "%b %d %Y %T"]]</small>
		<small>[expr $fsize/1000]K</small>
		<small><br>[string map { \n " " \f "" } $snip]</small>
	      </li>\n"

	    set DocDone($docid) 1
	}


	append reply "</ul>\n"
    }

    set reply
 }

 template html {
	{}
	{[format-row $tag $rank $mtime $fsize $url $file $title $snip]}
	{[format-page $pathmap]}
 }

