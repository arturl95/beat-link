meta:
  id: pdb_file
  title: DeviceSQL database export (probably generated by rekordbox)
  application: rekordbox
  file-extension:
    - pdb
  license: EPL-1.0
  endian: le

doc: |
  This is a relational database format designed to be efficiently used
  by very low power devices (there were deployments on 16 bit devices
  with 32K of RAM). Today you are most likely to encounter it within
  the Pioneer Professional DJ ecosystem, because it is the format that
  their rekordbox software uses to write USB and SD media which can be
  mounted in DJ controllers and used to play and mix music.

  It has been reverse-engineered to facilitate sophisticated
  integrations with light and laser shows, videos, and other musical
  instruments, by supporting deep knowledge of what is playing and
  what is coming next through monitoring the network communications of
  the players.

  The file is divided into fixed-size blocks. The first block has a
  header that establishes the block size, and lists the tables
  available in the database, identifying their types and the index of
  the first of the series of linked pages that make up that table.

  Each table is made up of a series of rows which may be spread across
  any number of pages. The pages start with a header describing the
  page and linking to the next page. The rest of the page is used as a
  heap: rows are scattered around it, and located using an index
  structure that builds backwards from the end of the page. Each row
  of a given type has a fixed size structure which links to any
  variable-sized strings by their offsets within the page.

  As changes are made to the table, some records may become unused,
  and there may be gaps within the heap that are too small to be used
  by other data. There is a bit map in the row index that identifies
  which rows are actually present. Rows that are not present must be
  ignored: they do not contain valid (or even necessarily well-formed)
  data.

  The majority of the work in reverse-engineering this format was
  performed by @henrybetts and @flesniak, for which I am hugely
  grateful. @GreyCat helped me learn the intricacies (and best
  practices) of Kaitai far faster than I would have managed on my own.

doc-ref: https://github.com/Deep-Symmetry/dysentery/blob/master/doc/Analysis.pdf

seq:
  - contents: [0, 0, 0, 0]
  - id: len_page
    type: u4
    doc: |
      The database page size, in bytes. Pages are referred to by
      index, so this size is needed to calculate their offset, and
      table pages have a row index structure which is built from the
      end of the page backwards, so finding that also requires this
      value.
  - id: num_tables
    type: u4
    doc: |
      Determines the number of table entries that are present. Each
      table is a linked list of pages containing rows of a particular
      type.
  - id: next_unused_page
    type: u4
    doc: |
      @flesinak said: "Not used as any `empty_candidate`, points
      past the end of the file."
  - type: u4
  - id: sequence
    type: u4
    doc: |
      @flesniak said: "Always incremented by at least one,
      sometimes by two or three."
  - contents: [0, 0, 0, 0]
  - id: tables
    type: table
    repeat: expr
    repeat-expr: num_tables
    doc: |
      Describes and links to the tables present in the database.

types:
  table:
    doc: |
      Each table is a linked list of pages containing rows of a single
      type. This header describes the nature of the table and links to
      its pages by index.
    seq:
      - id: type
        type: u4
        enum: page_type
        doc: |
          Identifies the kind of rows that are found in this table.
      - id: empty_candidate
        type: u4
      - id: first_page
        type: page_ref
        doc: |
          Links to the chain of pages making up that table. The first
          page seems to always contain similar garbage patterns and
          zero rows, but the next page it links to contains the start
          of the meaningful data rows.
      - id: last_page
        type: page_ref
    -webide-representation: '{type}'

  page_ref:
    doc: |
      An index which points to a table page (its offset can be found
      by multiplying the index by the `page_len` value in the file
      header). This type allows the linked page to be lazy loaded.
    seq:
      - id: index
        type: u4
        doc: |
          Identifies the desired page number.
    instances:
      body:
        doc: |
          When referenced, loads the specified page and parses its
          contents appropriately for the type of data it contains.
        io: _root._io
        pos: _root.len_page * index
        size: _root.len_page
        type: page

  page:
    doc: |
      A table page, consisting of a short header describing the
      content of the page and linking to the next page, followed by a
      heap in which row data is found. At the end of the page there is
      an index which locates all rows present in the heap via their
      offsets past the end of the page header.
    seq:
      - contents: [0, 0, 0, 0]
      - id: page_index
        doc: Matches the index we used to look up the page, sanity check?
        type: u4
      - id: type
        type: u4
        enum: page_type
        doc: |
          Identifies the type of information stored in the rows of this page.
      - id: next_page
        doc: |
          Index of the next page containing this type of rows. Points past
          the end of the file if there are no more.
        type: page_ref
      - type: u4
        doc: |
          @flesniak said: "sequence number (0->1: 8->13, 1->2: 22, 2->3: 27)"
      - size: 4
      - id: num_rows
        type: u1
        doc: |
          The number of rows on this page (controls the number of row
          index entries there are, but some of those may not be marked
          as present in the table due to deletion).
      - type: u1
        doc: |
          @flesniak said: "a bitmask (1st track: 32)"
      - type: u2
        doc: |
          @flesniak said: "25600 for strange blocks"
      - id: free_size
        type: u2
        doc: |
          Unused space (in bytes) in the page heap, excluding the row
          index at end of page.
      - id: used_size
        type: u2
        doc: |
          The number of bytes that are in use in the page heap.
      - type: u2
        doc: |
          @flesniak said: "(0->1: 2)"
      - id: num_rows_large
        type: u2
        doc: |
          @flesniak said: "usually <= num_rows except for playlist_map?"
      - type: u2
        doc: |
          @flesniak said: "1004 for strange blocks, 0 otherwise"
      - type: u2
        doc: |
          @flesniak said: "always 0 except 1 for history pages, num
          entries for strange pages?"

    instances:
      num_groups:
        value: '(num_rows - 1) / 16 + 1'
        doc: |
          The number of row groups that are present in the index. Each
          group can hold up to sixteen rows. All but the final one
          will hold sixteen rows.
      row_groups:
        type: 'row_group(_index)'
        repeat: expr
        repeat-expr: num_groups
        doc: |
          The actual row groups making up the row index. Each group
          can hold up to sixteen rows.

  row_group:
    doc: |
      A group of row indices, which are built backwards from the end
      of the page. Holds up to sixteen row offsets, along with a bit
      mask that indicates whether each row is actually present in the
      table.
    params:
      - id: group_index
        type: u2
        doc: |
          Identifies which group is being generated. They build backwards
          from the end of the page.
    instances:
      base:
        value: '_root.len_page - (group_index * 0x24)'
        doc: |
          The starting point of this group of row indices.
      row_present_flags:
        pos: base - 4
        type: u2
        doc: |
          Each bit specifies whether a particular row is present. The
          low order bit corresponds to the first row in this index,
          whose offset immediately precedes these flag bits. The
          second bit corresponds to the row whose offset precedes
          that, and so on.
      rows:
        type: row_ref(_index)
        repeat: expr
        repeat-expr: '(group_index < (_parent.num_groups - 1)) ? 16 : ((_parent.num_rows - 1) % 16 + 1)'
        doc: |
          The row offsets in this group.

  row_ref:
    doc: |
      An offset which points to a row in the table, whose actual
      presence is controlled by one of the bits in
      `row_present_flags`. This instance allows the row itself to be
      lazily loaded, unless it is not present, in which case there is
      no content to be loaded.
    params:
      - id: row_index
        type: u2
        doc: |
          Identifies which row within the row index this reference
          came from, so the correct flag can be checked for the row
          presence and the correct row offset can be found.
    instances:
      ofs_row:
        pos: '_parent.base - (6 + (2 * row_index))'
        type: u2
        doc: |
          The offset of the start of the row (in bytes past the end of
          the page header).
      present:
        value: '(((_parent.row_present_flags >> row_index) & 1) != 0 ? true : false)'
        doc: |
          Indicates whether the row index considers this row to be
          present in the table. Will be `false` if the row has been
          deleted.
        -webide-parse-mode: eager
      body:
        pos: ofs_row + 0x28
        type:
          switch-on: _parent._parent.type
          cases:
            'page_type::albums': album_row
            'page_type::artists': artist_row
        if: present
        doc: |
          The actual content of the row, as long as it is present.
        -webide-parse-mode: eager
    -webide-representation: 'present={present} {body.name.body.text}'

  album_row:
    doc: |
      A row that holds an artist name and ID.
    seq:
      - id: magic
        contents: [0x80, 0x00]
      - id: index_shift
        type: u2
        doc: TODO name from @flesniak, but what does it mean?
      - type: u4
      - id: artist_id
        doc: |
          Identifies the artist associated with the album.
        type: u4
      - id: id
        doc: |
          The unique identifier by which this album can be requested
          and linked from other rows (such as tracks).
        type: u4
      - type: u4
      - type: u1
        doc: |
          @flesniak says: "alwayx 0x03, maybe an unindexed empty string"
      - id: ofs_name
        type: u1
        doc: |
          The location of the variable-length name string, relative to
          the start of this row.
    instances:
      name:
        type: device_sql_string
        pos: _parent.ofs_row + 0x28 + ofs_name
        -webide-parse-mode: eager

  artist_row:
    doc: |
      A row that holds an artist name and ID.
    seq:
      - id: magic
        contents: [0x60, 0x00]
      - id: index_shift
        type: u2
        doc: TODO name from @flesniak, but what does it mean?
      - id: id
        doc: |
          The unique identifier by which this artist can be requested
          and linked from other rows (such as tracks).
        type: u4
      - type: u1
        doc: |
          @flesniak says: "alwayx 0x03, maybe an unindexed empty string"
      - id: ofs_name
        type: u1
        doc: |
          The location of the variable-length name string, relative to
          the start of this row.
    instances:
      name:
        type: device_sql_string
        pos: _parent.ofs_row + 0x28 + ofs_name
        -webide-parse-mode: eager

  device_sql_string:
    doc: |
      A variable length string which can be stored in a variety of
      different encodings. TODO: May need to skip leading zeros before
      the length byte.
    seq:
      - id: length_and_kind
        type: u1
        doc: |
          Mangled length of an ordinary ASCII string if odd, or a flag
          indicating another encoding with a longer length value to
          follow.
      - id: body
        type:
          switch-on: length_and_kind
          cases:
            '0x40': device_sql_long_ascii
            '0x90': device_sql_long_utf16be
            _: device_sql_short_ascii(length_and_kind)
        -webide-parse-mode: eager

  device_sql_short_ascii:
    doc: |
      An ASCII-encoded string up to 127 bytes long.
    params:
      - id: mangled_length
        type: u1
        doc: |
          Contains the actual length, incremented, doubled, and
          incremented again. Go figure.
    seq:
      - id: text
        type: str
        size: length
        encoding: ascii
    instances:
      length:
        value: '((mangled_length - 1) / 2) - 1'

  device_sql_long_ascii:
    doc: |
      An ASCII-encoded string preceded by a two-byte length field.
      TODO May need to skip a byte after the length!
           Have not found any test data.
    seq:
      - id: length
        type: u2
        doc: Contains the length of the string.
      - id: text
        type: str
        size: length
        encoding: ascii

  device_sql_long_utf16be:
    doc: |
      A UTF-16BE-encoded string preceded by a two-byte length field.
    seq:
      - id: length
        type: u2
        doc: |
          Contains the length of the string in bytes, including two trailing nulls.
      - id: text
        type: str
        size: length - 4
        encoding: utf-16be

enums:
  page_type:
    0:
      id: tracks
      doc: |
        Holds rows describing tracks, such as their title, artist,
        genre, artwork ID, playing time, etc.
    1:
      id: genres
      doc: |
        Holds rows naming musical genres, for reference by tracks and searching.
    2:
      id: artists
      doc: |
        Holds rows naming artists, for reference by tracks and searching.
    3:
      id: albums
      doc: |
        Holds rows naming albums, for reference by tracks and searching.
    4:
      id: labels
      doc: |
        Holds rows naming music labels, for reference by tracks and searching.
    5:
      id: keys
      doc: |
        Holds rows naming musical keys, for reference by tracks and searching.
    6:
      id: colors
      doc: |
        Holds rows naming color labels, for reference  by tracks and searching.
    7:
      id: playlists
      doc: |
        Holds rows containing playlists.
    8:
      id: playlist_map
      doc: |
        TODO figure out and explain
    9:
      id: unknown_9
    10:
      id: unknown_10
    11:
      id: unknown_11
    12:
      id: unknown_12
    13:
      id: artwork
      doc: |
        Holds rows pointing to album artwork images.
    14:
      id: unknown_14
    15:
      id: unknown_15
    16:
      id: columns
      doc: |
        TODO figure out and explain
    17:
      id: unknown_17
    18:
      id: unknown_18
    19:
      id: history
      doc: |
        Holds rows listing tracks played in performance sessions.
