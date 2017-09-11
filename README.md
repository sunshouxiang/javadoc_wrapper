javadoc_wrapper.pl - A javadoc wrapper enabling multi-lingual document generation
=========

Introduction
----

javadoc_wrapper.pl opens Java files specified in a list file, filters theirs lines and
save temporary files to a temporary directory, and calls javadoc to process those
temporary files.

Command line syntax
----

`javadoc_wrapper.pl [-locale <locale>] <list_file> [-- [javadoc options]]`

Examples

        javadoc_wrapper.pl list_file_of_java_src_files
        javadoc_wrapper.pl -locale zh_CN list_file_of_java_src_files
        javadoc_wrapper.pl -locale zh_CN list_file_of_java_src_files -- -locale zh_CN

The `locale` parameter for javadoc_wrapper.pl must contain only alphabets, digits and '_'. Its default
value is "default". Let's call the locale specified in the command line `document locale`.

Examples

        en
        en_US
        zh_CN
        ja

The `list_file` is a text file with each line being path of a Java source file. The paths must be absolute
or relative to current working directory.

Examples

        app/src/main/java/com/moon/doc_test/DocTest.java
        /home/moon/projects/doc/test/app/src/main/java/com/moon/doc_test/DocTest.java
        D:/work/projects/doc/test/app/src/main/java/com/moon/doc_test/DocTest.java

Encoding of Java source files must be utf-8.

Locale switching
----

Locales can be specified in javadoc comment block, like

`@locale locale_list`

where `locale_list` is locales separated by comma. The tag above means if `doccument locale` exists in
`locale_list`, the subsequent lines are printed to temporary file after macro substitution.

Locale list is set empty at the beginning of javadoc comment block. A locale tag with no locales specified
clears locale list too. If the locale list is empty, subsequent lines are always printed.

Examples

        /**
         * @locale zh_CN
         * 这是简体中文注释。
         * @locale zh_TW, zh_HK
         * 這是繁體中文註釋。
         * @locale default
         * This is English comment as default.
         * @locale
         * This line is always printed.
         */

Locale mapping
----

A locale can be mapped to another one, giving you convenience in document composition.

Examples

        /**
         * @locale en = default
         * @locale en_US = default
         * @locale en_GB = default
         * @locale zh_TW = zh_CN
        */

In the example, en, en_US and en_GB are all treated as "default", while zh_TW is treated as zh_CN, thus if you run

        javadoc_wrapper.pl -locale en

the document of "default" locale is created.

Inline text filtering
----

Text applies to certain locales can be specified in format

`${locale_list:document text}`

If the `document locale` exists in the locale list, the followed text excluding character '}' is printed.
Real '}' must be escaped with '$' ("$n" is converted to EOL so that you can write multi-line text).
Default locale ("default") will be used if the locale list is empty.

Examples

        /**
         * ${zh_CN:这是简体中文注释}${ja,en:This is English comment for both locale 'en' and locale 'ja'.}
         * ${:This is default comment in English.}
         * ${:This is default comment containing right brace $} in English.}
         * ${:Comment line 1$n * Comment line 2.}
         */

Macro
----

### Macro definition

A macro is defined with 'macro' tag.

`@macro NAME (locale_list:expanded document 1, locale_list:expanded document 2, ...)`

where NAME must contain only alphabets, digits and '_'. Real comma and right parentheis must be escaped with '$'
as they are used as delimiters ("$n" is converted to EOL so that you can write multi-line macro).

Examples

        /**
         * @macro FH (:file handle, zh_CN:文件句柄)
         * @macro CHRACTERS (:Tom (cat$)$, Jerry (mouse$), zh_CN:汤姆（猫），杰瑞（鼠）)
         * @macro GETTER (:Get #1.$n * @return #1, zh_CN:获取#1。$n * @return #1)
         * @macro SETTER (:Set #1.$n * @param #2 #1, zh_CN:设置#1。$n * @param #2 #1)
         * @macro TABLE_ROW (:<tr><td>#1</td><td>#2</td></tr>)
         */

The last example contains 3 arguments, #1, #2 and #3, which will be replaced with text arguments during expanding.
Real '#' in the definition must be escaped with '#' ("##" => "#").

### Auto-increasing integers

An auto-increasing integer is defined in format

`@int NAME (number1, number2)`

where number1 is the initial value, and number2 is the step, both should be 0 or positive.
Auto-increasing intergers may be used as serial IDs in lists. Every time an auto-increasing
integer is refered to, its current value is returned and then increased by the step.

Examples

        /**
         * @macro SECTION (1, 1)
         */

### Macro subsitution

Macros are refered to in format

`${macro_referer_list}`

`${macro_referer# [arg1, [arg2, ...]]}`

where macro_referer_list contains one or more referer separated by comma, and arg1, arg2 ... are optional arguments.
Arguments are separated by comma, so real ',', '$' and '}' must be escaped with '$'. Macro can be used recursively.

A macro_referer is in format

`name[*number][=back_ref]`

where the first option 'number' means the defined text of 'name' should be printed 'number' times, and the second option
'back_ref' means the expanded text (after 'number' times) should be added to macro dictionary with name being 'back_ref' and
locale being "default". This is useful when you do not want to use numbers directly for serial IDs.

If 'name' is an auto-increasing integer, 'number' can be omitted and the remaining individul '*' means the integer should
be reset to its initial value before substitution.

If 'name' exists in both macro dictionary and auto-increasing integer dictionary, the former takes precedence.

As a special case, if the braces after '$' enclose only white spaces, the white spaces are printed as is.

Examples

        /**
         * Table ${SECTION=TABLE}<br>
         * <table>
         * <tr><th>Characters</th><th>Planet</th></tr>
         * ${TABLE_ROW# ${CHRACTERS}$, The Duck, Earth}
         * ${TABLE_ROW# The Lion, ${    }${:Mars}${zh_CN:火星}}
         * </table>
         * Table ${TABLE} lists some lovely cartoon chracters.
         */

Multiple rounds
----

In the examples in previous section, we refer to the section number via a back-ref macro 'TABLE' in last sentence.
However, if we move the sentence to the very beginning, we cannot retrieve the macro as it is not created yet. In
this case we may use 'repeat' tags. As follows.

        /**
         * @repeat 2
         * Table $${TABLE} lists some lovely cartoon chracters.
         * Table ${SECTION=TABLE}<br>
         * <table>
         * <tr><th>Characters</th><th>Planet</th></tr>
         * ${TABLE_ROW# ${CHRACTERS}$, The Duck, Earth}
         * ${TABLE_ROW# The Lion, ${    }${:Mars}${zh_CN:火星}}
         * </table>
         * @repeat
         */

The first 'repeat' tag followed by a number 2 starts a 'repeat' block, the final 'repeat' tag without number ends the block.
The lines enclosed in the two 'repeat' tags are expanded twice ('2' times). In round 1, '$${TABLE}' is expanded
to '${TABLE}' and macro 'TABLE' is created with value being "1". In round 2, '${TABLE}' is replaced with "1".

jdoc.pl - A script to run javadoc_wrapper.pl easily
----

jdoc.pl assumes a fixed-name "jdoc.lst" of `list_file` and set charset/encoding to utf-8 when run javadoc_wrapper.pl. The documents are created in directory Document/jdoc/&lt;locale&gt;.

Command line syntax:

`jdoc.pl <locale> [javadoc options]`

Examples

        ./jdoc.pl -locale en_US
        ./jdoc.pl zh_CN -locale zh_CN

Version
----
1.0 - Sep 2017
