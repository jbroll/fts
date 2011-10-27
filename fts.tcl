#!/home/john/fts/kbsvq8.6-cli
#
 load /home/john/lib/libtclsqlite3.so

 set  verb QUIET
 proc verb { type message } { if { [regexp $::verb $type] } { puts "[format %10.10s $type] : $message" } }

 set columnweight { 5 1 } 
 
 proc database { database } { 
    if { [string index $database 0] ne "/" } { set ::database $::cfgdir/$database }
 }

 set excludes {}
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
	if { [string match $pattern $file] } { return 1 }
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
		    <td>$snip</td>
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

    foreach word [split [read [set fp [open $file]]]] {
	set ::stops($word) 1
    }
    close $fp
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
    set body [regsub -all {[,<>?\\~!@#$%^&*()_+]} $body { }]
    set indx $body

    if { [info exists ::stops] } {
	set indx {}

	foreach word [split $body] {
	    if { [string length $word] <= 2 } { continue }
	    if { [regexp {[[:lower:]]} $word] } {
		if { [string length $word] <= 3 } { continue }
		set word [string tolower $word]
	    }
	    if { [info exists ::stops($word)] } { continue }

	    append indx $word " "
	}
    }

    if { [info proc $tag] ne {} } { set title [$tag Title $file]
    } else { 			    set title [file root [file tail [string map { + { } _ { } - { } } $file]]] }


    if { [db eval { select rowid from documents where file = $file }] eq {} } {
	verb insert $file
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
 proc index-path! { tag path url rx } {
    foreach dir [glob -type d -directory $path -nocomplain *] {
	if { ![exclude? $dir/] } { index-path! $tag $dir $url $rx }
    }
    foreach file [glob -type f -directory $path -nocomplain *] {
	if { ![exclude? $file] } { index-file $tag $file [regsub $rx $file $url] }
    }
 }

 proc searchrank { matchinfo } {
     set score 0

  try {
     binary scan $matchinfo ii nphrase ncol

     for { set p 0 } { $p < $nphrase } { incr p } {
     for { set c 0 } { $c < $ncol    } { incr c } {
	binary scan $matchinfo x[expr 8 + 12 * ($c+$p*$ncol)]iii DocHits AllHits NDocs

	if { !$DocHits } { continue } 

	set score [expr $score + $DocHits/ double($AllHits) * [lindex $::columnweight $c]]
     } }
  } on error message {
      puts stderr $message
  }

     return $score
 }


 set config [file root $argv0].conf

 if { [string range [lindex $argv 0] 0 0] eq "@" } {
     set config [string range [lindex $argv 0] 1 end]
     set argv   [lrange $argv 1 end]
 } 

 set cfgdir [file dirname $config]

 if { [string range [lindex $argv 0] 0 0] eq "+" } {
     set   verb [string range [lindex $argv 0] 1 end]
     set ::verb ^(([string map { , .*)|( } $verb].*))$
     set argv   [lrange $argv 1 end]
 }

 try { source $::config } on error message { puts "fts: $message"; exit 1 }

 set command  [lindex $argv 0]

 switch $command {
  excludes { foreach exclude $::excludes { puts $exclude } ; exit }
  filters  { foreach { pattern action } $::filters { puts "[format %8.8s $pattern] : $action" } ; exit }

  docs   -
  index  -
  search {
    sqlite3 db $database
    db function searchrank searchrank

    catch { db eval { create virtual table searchtext using fts4(tokenize=porter, title text, body text); } }
    catch { db eval { create table documents ( tag, file, mtime, fsize, url ) } }
    catch { db eval { create index on documents ( file ) } }
  }
  default {
    puts "fts: unknown subcommand \"$command\""
    puts {
	fts [@<conf>] index [<file>]	 	- index a set of directories indicated in <conf>

		If the <file> aggument is given index the file.  Otherwise index all the index paths 
		given in the configuration file.

	fts [@<conf>] search    <query>		- seach the index for query
	fts [@<conf>] excludes 			- display the exclude patterns from <conf>
	fts [@<conf>] filters  			- display the filter  patterns from <conf>
	fts [@<conf>] docs			- display a table of documents in the index.

	Config file commands:

	  set tmp   <temporary-directory>	
	  database  <sqlite3-database-file>
	  stopwords <stop-words-file>

	  filter <glob-pattern> <extraction-command>

	  	%f  replacement
		@F replacement with filter chaining.

		File extension patterns of the form "*.ext" are not case sensative

	  exclude <glob-pattern> ...

	  index-path <tag> <path> [url] [regexp]
	  
	  	Index all files in the path, recursing to subdirectories.
		A url entry for the database is generated by calling:

		    set url [regsub $regexp $filepath $url]
		    
		The default values for url and regexp are {\1} and {%p(.*)}, where
		%p is substituted with the indexed path.  This generates the 
		file tail as the default url entry in search results.
	}
    exit 1
  } 
 }

 switch $command {
  index  {
    	if { [llength $argv] == 2 } {
	    set files [lindex $argv 1] 

	    if { $files eq "-" } { set files [read stdin] } 

	    foreach file $files {

	        foreach { tag path url rx } $::paths {
		    if { ![string first $path $file] } {
		        index-file $tag $file [regsub [string map [list %p $path] $rx] $file $url] yes
		    }
	        }
	    }
	} else {
	    foreach { tag path url rx } $::paths {
		index-path! $tag $path $url [string map [list %p $path] $rx]
	    }
	}
  }
  search { 
    if { [lindex $argv 1] eq "-t" } {
 	set template [lindex $argv 2]
        set query    [lrange $argv 3 end]
    } else {
        set query    [lrange $argv 1 end]
 	set template text
    }

    set template $::templates($template)

    foreach { tag path url rx } $::paths {
	lappend pathmap $path/ {}
    }

    if { [lindex $template 0] ne {} } { puts [subst [lindex $template 0]] }

    db eval { select docid, searchrank(matchinfo(searchtext)) as rank, snippet(searchtext) as snip 
	      from  searchtext
	      where searchtext match $query
 	      order by rank desc; } {
        db eval { select rowid, tag, mtime, fsize, url, file from documents where rowid = $docid ; } {
	    if { [set row [subst [lindex $template 1]]] ne {} } { puts $row }
        }
    }

    if { [lindex $template 2] ne {} } { puts [subst [lindex $template 2]] }
  }
  docs {
      switch [lindex $argv 1] {
	  rm {
	      set docids [lrange $argv 2 end]
	      if { $docids eq "-" } { set docids [read stdin] } 

	      foreach docid $docids {
	          db eval { 
		    begin  transaction  ;
		    delete from documents  where rowid = $docid ;
		    delete from searchtext where docid = $docid ;
	            commit transaction
	          }
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
	  default {
	    puts "rowid	mtime	fsize	url	file"
	    puts "-----	-----	-----	---	----"
	    db eval { select rowid, mtime, fsize, url, file from documents } {
		puts "$rowid	$mtime	$fsize	$url	$file"
	    }
	  }
      }
  }
 }

