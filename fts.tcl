#!/home/john/fts/kbsvq8.6-cli
#
 load /home/john/lib/libtclsqlite3.so

 set  verb QUIET
 proc verb { type message } { if { [regexp $::verb $type] } { puts "[format %10.10s $type] : $message" } }

set wTitle 10
set wBody   1


 proc K { x y } { set x }
 proc shift { V } { upvar $V v; K [lindex $v 0] [set v [lrange [K $v [unset v]] 1 end]] }
 proc yank  { opt listName { default {} } } {
     upvar $listName list

     if { [set n [lsearch $list $opt]] < 0 } { return $default }

     K [lindex $list $n+1] [set list [lreplace [K $list [unset list]] $n $n+1]]
 }
 proc yink { opt listName { bool 1 } } {
    upvar $listName list

    if { [set n [lsearch $list $opt]] < 0 } {
	if { $bool } {  return 0
	} else {        return {} }
    }

    set list [lreplace [K $list [unset list]] $n $n]

    if { $bool } {      return 1
    } else {            return $opt }
 }

 proc config {} {
     try { uplevel #0 { source $config } } on error message { puts "[file root $::argv0]: $message"; exit 1 }
 }

 proc database { database } { 
    if { [string index $database 0] ne "/" } { set ::database $::cfgdir/$database
    } else {				       set ::database           $database }

    verb database $::database
 }

 proc exclude  { args } {
    foreach pattern $args {
	lappend ::excludes $pattern
	if { [regexp {^\*\.[a-z0-9]+$} $pattern] } {
	    lappend ::excludes [string toupper $pattern]
	}
    }
 }
 proc exclude? { file } {
    foreach pattern $::excludes {
	if { [string match $pattern $file] } { verb excluded $file ;  return 1 }
    }

    return 0
 }

 array set templates {
	html {	{<h2>Search Results</h2>
		 <p>
		 <table>
		}
		{<tr>
		    <td><a href=\"$url\">[string map $pathmap $file]</a></td></tr>
		    <td>[string map { \n " " \f "" } $snip]</td>
		    <td><small>[string map { { } {&nbsp;} } [clock format $mtime -format "%b %d %Y %T"]]</small></td>
		    <td><small>[expr $fsize/1000]K</small></td>
		}
		{</table>}
	}
	text { {} {$tag $rank	$mtime	$fsize	$url	$file} {} }
 }

 proc template { type template } { set ::templates($type) $template }

 proc filter  { pattern args } {
    lappend ::filters $pattern $args
    if { [regexp {^\*\.[a-z0-9]+$} $pattern] } {
	lappend ::filters [string toupper $pattern] $args
    }
 }
 proc filter? { file } {
    foreach { pattern action } $::filters {
	if { [string match $pattern $file] } {
	    if { [string first @F $action] == -1 } {
		return [list [list [string map [list %f $file] $action]]]
	    } else {
		set f $file
		set F [string map [list [string range $pattern 1 end] {}] $::tmp/[file tail $file]]
		set actions [list [string map [list %f $f @F $F] $action] "$F"]

		if { [set action [filter? $F]] eq {} } {
		    return {}
		} else { 
		    return [list $actions {*}$action]
		}
	    }
        }
    }

    return {}
 }
 proc filter! { actions } {
    set tmpfiles {}

    foreach action [lrange $actions 0 end-1] {
	foreach { action tmpfile } $action {}
        try { exec -ignorestderr {*}$action
	} on error message {
	    puts $message
	}

	lappend tmpfiles $tmpfile
    }

    set indx {}
    set body {}
    try {
	set body [exec -ignorestderr {*}[lindex [lindex $actions end] 0]] 
    } on error message {
	puts "tried: [lindex [lindex $actions end] 0]"
	puts $message
    } finally {
	if { $tmpfiles ne {} } { exec rm -f $tmpfiles }
    }

    return $body
 }

 proc stopwords { file } {
    if { [string index $file 0] ne "/" } { set file $::cfgdir/$file }

    foreach word [split [K [read [set fp [open $file]]] [close $fp]]] {
	set ::stops($word) 1
    }
 }

 proc index-file { tag file url { force no } } {
    if { ![llength [set actions [filter? $file]]] } {
	verb unindexed $file
	return
    }

    try {
        set xtime [file mtime $file]
        set xsize [file size  $file]
    } on error message {
	puts $message
	return
    } 

    if { !$force } {
	db eval { select mtime from documents where file = $file } {
	    if { $mtime >= $xtime } {
		verb unchanged $file
		return
	    }
	}
    }

    set body [filter! $actions]
    set body [regsub -all {\m[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?\M} $body { }]
    set body [regsub -all {[^-:;,<>?\\~!@#$%^&*()_+ a-zA-Z0-9.]} $body { }]
    set body [regsub -all  {[-:;,<>?\\~!@#$%^&*()_+.]{3,}} $body { }]
    set body [regsub -all {[ \t\n]+} $body { }]
    set indx $body

    if { [info exists ::stops] } {
	set indx {}

	foreach word [split $body] {
	    if { [string length $word] <= 2 }     { continue }
	    if { [regexp {[[:lower:]]} $word] } {
		if { [string length $word] <= 3 } { continue }
		set word [string tolower $word]
	    }
	    if { [info exists ::stops($word)] }   { continue }

	    append indx $word " "
	}
    }

    if { [info proc $tag] ne {} } { set title [$tag Title $file]
    } else { 			    set title [file root [file tail [string map { + { } _ { } - { } } $file]]] }


    if { [db eval { select rowid from documents where file = $file }] eq {} } {
	verb insert "$tag $file $url"
	db eval {
	    begin  transaction  ;
	    insert into  documents (  tag,  file,  mtime,  fsize,  url )
			    values ( $tag, $file, $xtime, $xsize, $url ) ;
	    insert into searchtext ( docid,                title,  body )
			    values ( last_insert_rowid(), $title, $indx ) ;
	    commit transaction
	}
    } else { 
	verb update $file
	db eval {
	    begin  transaction  ;
	    update  documents set mtime = $xtime, fsize = $xsize, url = $url where file = $file ;
	    update searchtext set title = $title, body = $body
		    where docid = ( select rowid from documents where file = $file ) ;
	    commit transaction
	} 
    }
 }

 proc index-path  { tag path { url {\1} } { rx %p/(.*) } } { lappend ::paths $tag $path $url $rx }
 proc index-path! { tag path url rx force } {
    foreach dir [glob -type d -directory $path -nocomplain *] {
	if { ![exclude? $dir/] } { index-path! $tag $dir $url $rx $force }
    }

    if { [file type $path] ne "directory" } {
	if { ![exclude? $path] } { index-file $tag $path [regsub $rx $path $url] $force }
    } else {
	foreach file [glob -type f -directory $path -nocomplain *] {
	    if { ![exclude? $file] } { index-file $tag $file [regsub $rx $file $url] $force }
	}
    }
 }

 proc searchrank { matchinfo args } {
  set score 0

  try {
     binary scan $matchinfo ii nphrase ncol

     for { set p 0 } { $p < $nphrase } { incr p } {
     for { set c 0 } { $c < $ncol    } { incr c } {
	binary scan $matchinfo x[expr 8 + 12 * ($c+$p*$ncol)]iii DocHits AllHits NDocs

	if { !$DocHits } { continue } 

	set score [expr $score + $DocHits/ double($AllHits) * [lindex $args $c]]
     } }
  } on error message {
      puts stderr $message
  }

  return $score
 }


 set config [file root $argv0].conf

 if { [string range [lindex $argv 0] 0 0] eq "@" } {
     set config [string range [shift argv] 0 0]
 } 

 set cfgdir [file dirname $config]

 if { [string range [lindex $argv 0] 0 0] eq "+" } {
     set   verb [string range [lindex $argv 0] 1 end]
     if { $verb eq "+" } { set verb .*
     } else {              set ::verb ^(([string map { , .*)|( } $verb].*))$ }
     set argv   [lrange $argv 1 end]
 }

 proc usage { fp } {
    puts $fp {
	fts [@<conf>] check 			- check that all the documents in the index
						  still exist.  Remove any that do not exist.
	fts [@<conf>] index [<files>]	 	- create of update the search index
	    
	    If no additional arguments are given, index a set of directories
	    indicated in the configuration file <conf> with the index-path directives.
	    
	    Or index the files (and directories) given on the command line.  When
	    indexing files, they must be included within the paths covered by
	    index-path directives in the configuration file.

	fts [@<conf>] excludes 			- display the exclude patterns from <conf>
	fts [@<conf>] filters  			- display the filter  patterns from <conf>
	fts [@<conf>] list 			- display a table of documents in the index.
	fts [@<conf>] search [-t tmpl]  <query>	- seach the index for query

	    The search command produces a table of search results...

	    The optional -t allows specification of an optional template.  Two templates are 
	    included on the source, text and html.  The default is text.

	fts [@<conf>] rm docid <docids ..>	- remove documents by docid.
	fts [@<conf>] rm file  <files  ..>	- remove documents by file path.

	Finding the config file:

	  The full path to the configuration file may be specified on the command line as the 
	  first argument, prefixed with the "@" symbol.  If this is not specified the name of
	  the executable will used as the name of the config file by suffixing ".conf" to it.

	Config file commands:

	  set tmp   <temporary-directory>

	  set wTitle <weight of title text>	# Weight is positive a real number 
	  set wBody  <weight of body text>

	  database  <sqlite3-database-file>
	  stopwords <stop-words-file>

	  filter <pattern> <extraction-command>

	    Any indexing file candidate that matches the glob style pattern will have
	    text extracted from it by executing the extraction command.  The "%f" and 
	    "@F" tokens in the extraction command string will be replaced with the file
	    name matching the pattern.  The extraction command will be executed and its
	    standard output used as the text to index.

	    If the replacement token "@F" is found in the extraction command string and
	    the pattern  is of the form "*.xxx" the rule is chained.  The matched extension
	    will be removed from the file name and the result will be matched against the
	    list of extraction filters again.
	   
	    File extension patterns of the form "*.xxx" are not case sensative.

	  exclude <glob-pattern> ...

	  index-path <tag> <path> [url] [regexp]
      
	    Index all files in the path, recursing to subdirectories.
	    A url entry for the database is generated by calling:

		set url [regsub $regexp $filepath $url]
		
	    The default values for url and regexp are {\1} and {%p(.*)}, where
	    %p is substituted with the indexed path.  This generates the 
	    file tail as the default url entry in search results.

	  template name { header rows footer }

	    Declair a template whose name may be used with the -t option to search.  The 
	    template is a list of three strings that will be expanded with subst to produce
	    the results of the search.  The first string is expanded before the search, it 
	    represents the header of the result.  When the header string is expaneded with
	    subst, the value $query is available.

	    The seconds string is expanded once for each row. The values $rowid, $tag,
	    $mtime, $fsize, $url, $file assiciated with the search result document are available
	    with the string is expanded.

	    The third string is expanded after the search results have been generated and
	    represents the footer of the search results.

	    If the result of any individual template expansion is an empty string the result is 
	    ignored.  If the oranization of the search results needs to be returned in an order 
	    different from the search ranking, the parts of a template to be utilized as callbacks
	    where search results are accumulated in calls to the row template, transformed and
	    returned in the footer.
    }
    exit 1
 }

 if { ![llength $argv] } { usage stdout }

 set command  [shift argv]

 config

 switch $command {
  excludes { config; foreach exclude $::excludes { puts $exclude } ; exit }
  filters  { config; foreach { pattern action } $::filters { puts "[format %8.8s $pattern] : $action" } ; exit }
 }

 sqlite3 db $database
 db timeout 3000
 db function searchrank searchrank

 catch { db eval { create virtual table searchtext using fts4(tokenize=porter, title text, body text); } }
 catch { db eval { create table documents ( tag, file, mtime, fsize, url ) } }

 switch $command {
  index  {
        set force [yink -f argv 1]

    	if { [llength $argv] == 0 } {
	    foreach { tag path url rx } $::paths {
		index-path! $tag $path $url [string map [list %p $path] $rx] $force
	    }
	} else {
	    if { $argv eq "-" } { set files [read stdin] } 

	    foreach file $argv {
	        foreach { tag path url rx } $::paths {
		    if { ![string first $path $file] } {
		        index-path! $tag $file $url [string map [list %p $path] $rx] $force
		    }
	        }
	    }
	}
  }
  search { 
    set template [yank -t argv text]
    set query $argv

    set template $::templates($template)

    foreach { tag path url rx } $::paths {
	lappend pathmap $path/ {}
    }

    if { [lindex $template 0] ne {} } { puts [subst [lindex $template 0]] }

    db eval { select docid, title, searchrank(matchinfo(searchtext), $::wTitle, $::wBody) as rank, snippet(searchtext) as snip 
	      from  searchtext
	      where searchtext match $query
 	      order by rank desc; } {
        db eval { select rowid, tag, mtime, fsize, url, file from documents where rowid = $docid ; } {
	    if { [set row [subst [lindex $template 1]]] ne {} } { puts $row }
        }
    }

    if { [lindex $template 2] ne {} } { puts [subst [lindex $template 2]] }
  }
  list {
      puts "rowid	tag	mtime	fsize	url	file"
      puts "-----	---	-----	-----	---	----"
      db eval { select rowid, tag, mtime, fsize, url, file from documents } {
	  puts "$rowid	$tag	$mtime	$fsize	$url	$file"
      }
  }
  check {
    db eval { select rowid, mtime, fsize, url, file from documents } {
	if { ![file exists $file] } {
	  db eval { 
	    begin  transaction  ;
	    delete from documents  where rowid = $rowid ;
	    delete from searchtext where docid = $rowid ;
	    commit transaction
	  }
	}
    }
  }
  rm {
      set submethod [shift argv]

      switch $submethod {
            verb docs-rm $argv
	    set type [shift argv]

	    if { $argv eq "-" } { set argv [read stdin] }

	    if { $type eq "file" } {
		set docids {}

		foreach file $argv {
		    db eval { select rowid from documents where file = $file } {
		        verb docs-rm-file "$rowid : $file"
			lappend docids $rowid
		    }
		}
	    } else {
		set docids $argv
	    }

	    foreach docid $docids {
		  verb docs-rmid $docid
	          db eval { 
		    begin  transaction  ;
		    delete from documents  where rowid = $docid ;
		    delete from searchtext where docid = $docid ;
	            commit transaction
	          }
	    }
	  }
      }
 }

