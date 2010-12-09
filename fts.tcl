#!/home/john/bin/tclkit8.6
#
 load /home/john/lib/libtclsqlite3.so

 set  verb QUIET
 proc verb { type message } { if { [regexp $::verb $type] } { puts "[format %10.10s $type] : $message" } }
 
 proc database { database } { set ::database $database }

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
    foreach word [split [read [set fp [open $file]]]] {
	set ::stops($word) 1
    }
    close $fp
 }

 proc index-file { file url } {
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

    db eval { select mtime from documents where file = $file } {
	if { $mtime >= $xtime } {
	    verb unchanged $file
	    return
	}
    }

    set body [filter! $actions]
    set body [regsub -all {\m[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?\M} $body { }]
    set body [regsub -all {[,<>?\\~!@#$%^&*()_+]} $body { }]

    foreach word [split $body] {
	if { [string length $word] <= 2 } { continue }
	if { [regexp {[[:lower:]]} $word] } {
	    if { [string length $word] <= 3 } { continue }
	    set word [string tolower $word]
	}
	if { [info exists ::stops($word)] } { continue }

	append indx $word " "
    }

    if { [db eval { select rowid from documents where file = @file }] eq {} } {
	verb insert $file
	db eval {
	    begin  transaction  ;
	    insert into documents  ( file, mtime, fsize, url ) values ( $file, $xtime, $xsize, $url ) ;
	    insert into searchtext ( docid, body ) values ( last_insert_rowid(), $indx ) ;
	    commit transaction
	}
    } else { 
	verb update $file
	db eval {
	    begin  transaction  ;
	    update documents set mtime = $xtime, fsize = $xsize, url = $url where file = $file ;
	    update searchtext set body = @body
		    where docid = ( select rowid from documents where file = $file ) ;
	    commit transaction
	} 
    }
 }

 proc index-path  { path { url {\1} } { rx %p/(.*) } } { lappend ::paths $path $url $rx }
 proc index-path! { path url rx } {
    foreach dir [glob -type d -directory $path -nocomplain *] {
	if { ![exclude? $dir/] } { index-path! $dir $url $rx }
    }
    foreach file [glob -type f -directory $path -nocomplain *] {
	if { ![exclude? $file] } { index-file  $file [regsub $rx $file $url] }
    }
 }

 set config [file root [file tail $argv0]].conf

 if { [lindex $argv 0] eq "@" } {
     set config [string range 1 end [lindex $argv 0]]
     set argv   [lrange $argv 1 end]
 } 

 try { source $::config } on error message { puts "fts: $message"; exit 1 }

 set command  [lindex $argv 0]

 proc searchrank { matchinfo } {
    binary scan $matchinfo iiiii nphrase ncol 1 2 3
    return $1
 }

 switch $command {
  excludes { foreach exclude $::excludes { puts $exclude } ; exit }
  filters  { foreach { pattern action } $::filters { puts "[format %8.8s $pattern] : $action" } ; exit }

  docs   -
  index  -
  search {
    sqlite3 db $database
    db enable_load_extension 1
    db function searchrank searchrank

    catch { db eval { create virtual table searchtext using fts3(tokenize=porter, body text); } }
    catch { db eval { create table documents ( file, mtime, fsize, url ) } }
    catch { db eval { create index on documents ( file ) } }
  }
  default {
    puts "fts: unknown subcommand \"$command\""
    puts {
	fts index    <conf> <verb>		- index a set of directories indicated in <conf>

	    verbosity is a comma separated list of the message types insert, update, unindexed
	    , unchanged,exclude or a unique prefix of them.

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

	  index-path <path> [url] [regexp]
	  
	  	Index all files in the path, recursint to subdirectories.
		A url entry for the database is generated by calling:

		    set url [regsub $regexp $filepath $url]
		    
		The default values for url and regexp are {\1} and {%p(.*)}, where
		%p is substituted with the indexed path.  This generateds the 
		file tail as the default url entry in search results.
	}
    exit 1
  } 
 }

 switch $command {
  index  {
    	if { [llength $argv] == 3 } { set ::verb ^(([string map { , .*)|( } [lindex $argv 2]].*))$ }

    	foreach { path url rx } $::paths { index-path! $path $url [string map [list %p $path] $rx] }
  }
  search { 
    set query    [lrange $argv 1 end]

    db eval { select docid, searchrank(matchinfo(searchtext)) as rank from searchtext
	      where body match @query
 	      order by searchrank(matchinfo(searchtext)) desc; } {
        db eval { select rowid, mtime, fsize, url, file from documents where rowid = $docid ; } {
	    puts "$rank	$mtime	$fsize	$url	$file"
        }
    }
  }
  docs {
      switch [lindex $argv 1] {
	  rm {
	      set docid [lindex $argv 2]
	      db eval { 
		begin  transaction  ;
		delete from documents  where rowid = $docid ;
		delete from searchtext where docid = $docid ;
	        commit transaction
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

