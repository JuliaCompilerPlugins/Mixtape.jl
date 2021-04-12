	.section	__TEXT,__text,regular,pure_instructions
	.build_version macos, 10, 15
	.globl	_julia_f_1515                   ## -- Begin function julia_f_1515
	.p2align	4, 0x90
_julia_f_1515:                          ## @julia_f_1515
Lfunc_begin0:
	.file	1 "/Users/mccoybecker/dev/Mixtape.jl/examples/static_compile.jl"
	.loc	1 8 0                           ## /Users/mccoybecker/dev/Mixtape.jl/examples/static_compile.jl:8:0
	.cfi_startproc
## %bb.0:                               ## %top
	pushq	%rbx
	.cfi_def_cfa_offset 16
	.cfi_offset %rbx, -16
	movq	%rdi, %rbx
	callq	_julia.ptls_states
Ltmp0:
	.file	2 "./int.jl"
	.loc	2 442 0 prologue_end            ## int.jl:442:0
	cmpq	$1, %rbx
	jle	LBB0_1
Ltmp1:
## %bb.2:                               ## %L4
	.loc	2 86 0                          ## int.jl:86:0
	leaq	-1(%rbx), %rdi
	callq	_julia_f_1515
Ltmp2:
	.loc	2 87 0                          ## int.jl:87:0
	addq	%rbx, %rax
	popq	%rbx
	retq
Ltmp3:
LBB0_1:                                 ## %L3
	.loc	2 442 0                         ## int.jl:442:0
	movl	$1, %eax
	popq	%rbx
	retq
Ltmp4:
Lfunc_end0:
	.cfi_endproc
                                        ## -- End function
	.globl	_jfptr_f_1516                   ## -- Begin function jfptr_f_1516
	.p2align	4, 0x90
_jfptr_f_1516:                          ## @jfptr_f_1516
Lfunc_begin1:
	.cfi_startproc
## %bb.0:                               ## %top
	pushq	%rbx
	.cfi_def_cfa_offset 16
	.cfi_offset %rbx, -16
	movq	%rsi, %rbx
	callq	_julia.ptls_states
	movq	(%rbx), %rax
	movq	(%rax), %rdi
	callq	_julia_f_1515
	movq	%rax, %rdi
	callq	_jl_box_int64
	popq	%rbx
	retq
Lfunc_end1:
	.cfi_endproc
                                        ## -- End function
	.section	__DWARF,__debug_abbrev,regular,debug
Lsection_abbrev:
	.byte	1                               ## Abbreviation Code
	.byte	17                              ## DW_TAG_compile_unit
	.byte	1                               ## DW_CHILDREN_yes
	.byte	37                              ## DW_AT_producer
	.byte	14                              ## DW_FORM_strp
	.byte	19                              ## DW_AT_language
	.byte	5                               ## DW_FORM_data2
	.byte	3                               ## DW_AT_name
	.byte	14                              ## DW_FORM_strp
	.byte	16                              ## DW_AT_stmt_list
	.byte	23                              ## DW_FORM_sec_offset
	.byte	27                              ## DW_AT_comp_dir
	.byte	14                              ## DW_FORM_strp
	.ascii	"\264B"                         ## DW_AT_GNU_pubnames
	.byte	25                              ## DW_FORM_flag_present
	.ascii	"\341\177"                      ## DW_AT_APPLE_optimized
	.byte	25                              ## DW_FORM_flag_present
	.byte	17                              ## DW_AT_low_pc
	.byte	1                               ## DW_FORM_addr
	.byte	18                              ## DW_AT_high_pc
	.byte	6                               ## DW_FORM_data4
	.byte	0                               ## EOM(1)
	.byte	0                               ## EOM(2)
	.byte	2                               ## Abbreviation Code
	.byte	46                              ## DW_TAG_subprogram
	.byte	0                               ## DW_CHILDREN_no
	.byte	110                             ## DW_AT_linkage_name
	.byte	14                              ## DW_FORM_strp
	.byte	3                               ## DW_AT_name
	.byte	14                              ## DW_FORM_strp
	.byte	63                              ## DW_AT_external
	.byte	25                              ## DW_FORM_flag_present
	.ascii	"\341\177"                      ## DW_AT_APPLE_optimized
	.byte	25                              ## DW_FORM_flag_present
	.byte	32                              ## DW_AT_inline
	.byte	11                              ## DW_FORM_data1
	.byte	0                               ## EOM(1)
	.byte	0                               ## EOM(2)
	.byte	3                               ## Abbreviation Code
	.byte	46                              ## DW_TAG_subprogram
	.byte	1                               ## DW_CHILDREN_yes
	.byte	17                              ## DW_AT_low_pc
	.byte	1                               ## DW_FORM_addr
	.byte	18                              ## DW_AT_high_pc
	.byte	6                               ## DW_FORM_data4
	.ascii	"\347\177"                      ## DW_AT_APPLE_omit_frame_ptr
	.byte	25                              ## DW_FORM_flag_present
	.byte	64                              ## DW_AT_frame_base
	.byte	24                              ## DW_FORM_exprloc
	.byte	110                             ## DW_AT_linkage_name
	.byte	14                              ## DW_FORM_strp
	.byte	3                               ## DW_AT_name
	.byte	14                              ## DW_FORM_strp
	.byte	58                              ## DW_AT_decl_file
	.byte	11                              ## DW_FORM_data1
	.byte	59                              ## DW_AT_decl_line
	.byte	11                              ## DW_FORM_data1
	.byte	63                              ## DW_AT_external
	.byte	25                              ## DW_FORM_flag_present
	.ascii	"\341\177"                      ## DW_AT_APPLE_optimized
	.byte	25                              ## DW_FORM_flag_present
	.byte	0                               ## EOM(1)
	.byte	0                               ## EOM(2)
	.byte	4                               ## Abbreviation Code
	.byte	29                              ## DW_TAG_inlined_subroutine
	.byte	0                               ## DW_CHILDREN_no
	.byte	49                              ## DW_AT_abstract_origin
	.byte	19                              ## DW_FORM_ref4
	.byte	85                              ## DW_AT_ranges
	.byte	23                              ## DW_FORM_sec_offset
	.byte	88                              ## DW_AT_call_file
	.byte	11                              ## DW_FORM_data1
	.byte	89                              ## DW_AT_call_line
	.byte	11                              ## DW_FORM_data1
	.byte	0                               ## EOM(1)
	.byte	0                               ## EOM(2)
	.byte	5                               ## Abbreviation Code
	.byte	29                              ## DW_TAG_inlined_subroutine
	.byte	0                               ## DW_CHILDREN_no
	.byte	49                              ## DW_AT_abstract_origin
	.byte	19                              ## DW_FORM_ref4
	.byte	17                              ## DW_AT_low_pc
	.byte	1                               ## DW_FORM_addr
	.byte	18                              ## DW_AT_high_pc
	.byte	6                               ## DW_FORM_data4
	.byte	88                              ## DW_AT_call_file
	.byte	11                              ## DW_FORM_data1
	.byte	89                              ## DW_AT_call_line
	.byte	11                              ## DW_FORM_data1
	.byte	0                               ## EOM(1)
	.byte	0                               ## EOM(2)
	.byte	0                               ## EOM(3)
	.section	__DWARF,__debug_info,regular,debug
Lsection_info:
Lcu_begin0:
.set Lset0, Ldebug_info_end0-Ldebug_info_start0 ## Length of Unit
	.long	Lset0
Ldebug_info_start0:
	.short	4                               ## DWARF version number
.set Lset1, Lsection_abbrev-Lsection_abbrev ## Offset Into Abbrev. Section
	.long	Lset1
	.byte	8                               ## Address Size (in bytes)
	.byte	1                               ## Abbrev [1] 0xb:0x89 DW_TAG_compile_unit
	.long	0                               ## DW_AT_producer
	.short	31                              ## DW_AT_language
	.long	6                               ## DW_AT_name
.set Lset2, Lline_table_start0-Lsection_line ## DW_AT_stmt_list
	.long	Lset2
	.long	67                              ## DW_AT_comp_dir
                                        ## DW_AT_GNU_pubnames
                                        ## DW_AT_APPLE_optimized
	.quad	Lfunc_begin0                    ## DW_AT_low_pc
.set Lset3, Lfunc_end0-Lfunc_begin0     ## DW_AT_high_pc
	.long	Lset3
	.byte	2                               ## Abbrev [2] 0x2a:0xa DW_TAG_subprogram
	.long	69                              ## DW_AT_linkage_name
	.long	72                              ## DW_AT_name
                                        ## DW_AT_external
                                        ## DW_AT_APPLE_optimized
	.byte	1                               ## DW_AT_inline
	.byte	2                               ## Abbrev [2] 0x34:0xa DW_TAG_subprogram
	.long	76                              ## DW_AT_linkage_name
	.long	78                              ## DW_AT_name
                                        ## DW_AT_external
                                        ## DW_AT_APPLE_optimized
	.byte	1                               ## DW_AT_inline
	.byte	2                               ## Abbrev [2] 0x3e:0xa DW_TAG_subprogram
	.long	81                              ## DW_AT_linkage_name
	.long	83                              ## DW_AT_name
                                        ## DW_AT_external
                                        ## DW_AT_APPLE_optimized
	.byte	1                               ## DW_AT_inline
	.byte	3                               ## Abbrev [3] 0x48:0x4b DW_TAG_subprogram
	.quad	Lfunc_begin0                    ## DW_AT_low_pc
.set Lset4, Lfunc_end0-Lfunc_begin0     ## DW_AT_high_pc
	.long	Lset4
                                        ## DW_AT_APPLE_omit_frame_ptr
	.byte	1                               ## DW_AT_frame_base
	.byte	87
	.long	88                              ## DW_AT_linkage_name
	.long	86                              ## DW_AT_name
	.byte	1                               ## DW_AT_decl_file
	.byte	8                               ## DW_AT_decl_line
                                        ## DW_AT_external
                                        ## DW_AT_APPLE_optimized
	.byte	4                               ## Abbrev [4] 0x61:0xb DW_TAG_inlined_subroutine
	.long	42                              ## DW_AT_abstract_origin
.set Lset5, Ldebug_ranges0-Ldebug_range ## DW_AT_ranges
	.long	Lset5
	.byte	1                               ## DW_AT_call_file
	.byte	0                               ## DW_AT_call_line
	.byte	5                               ## Abbrev [5] 0x6c:0x13 DW_TAG_inlined_subroutine
	.long	52                              ## DW_AT_abstract_origin
	.quad	Ltmp1                           ## DW_AT_low_pc
.set Lset6, Ltmp2-Ltmp1                 ## DW_AT_high_pc
	.long	Lset6
	.byte	1                               ## DW_AT_call_file
	.byte	0                               ## DW_AT_call_line
	.byte	5                               ## Abbrev [5] 0x7f:0x13 DW_TAG_inlined_subroutine
	.long	62                              ## DW_AT_abstract_origin
	.quad	Ltmp2                           ## DW_AT_low_pc
.set Lset7, Ltmp3-Ltmp2                 ## DW_AT_high_pc
	.long	Lset7
	.byte	1                               ## DW_AT_call_file
	.byte	0                               ## DW_AT_call_line
	.byte	0                               ## End Of Children Mark
	.byte	0                               ## End Of Children Mark
Ldebug_info_end0:
	.section	__DWARF,__debug_ranges,regular,debug
Ldebug_range:
Ldebug_ranges0:
.set Lset8, Ltmp0-Lfunc_begin0
	.quad	Lset8
.set Lset9, Ltmp1-Lfunc_begin0
	.quad	Lset9
.set Lset10, Ltmp3-Lfunc_begin0
	.quad	Lset10
.set Lset11, Ltmp4-Lfunc_begin0
	.quad	Lset11
	.quad	0
	.quad	0
	.section	__DWARF,__debug_str,regular,debug
Linfo_string:
	.asciz	"julia"                         ## string offset=0
	.asciz	"/Users/mccoybecker/dev/Mixtape.jl/examples/static_compile.jl" ## string offset=6
	.asciz	"."                             ## string offset=67
	.asciz	"<="                            ## string offset=69
	.asciz	"<=;"                           ## string offset=72
	.asciz	"-"                             ## string offset=76
	.asciz	"-;"                            ## string offset=78
	.asciz	"+"                             ## string offset=81
	.asciz	"+;"                            ## string offset=83
	.asciz	"f"                             ## string offset=86
	.asciz	"julia_f_1515"                  ## string offset=88
	.section	__DWARF,__apple_names,regular,debug
Lnames_begin:
	.long	1212240712                      ## Header Magic
	.short	1                               ## Header Version
	.short	0                               ## Header Hash Function
	.long	8                               ## Header Bucket Count
	.long	8                               ## Header Hash Count
	.long	12                              ## Header Data Length
	.long	0                               ## HeaderData Die Offset Base
	.long	1                               ## HeaderData Atom Count
	.short	1                               ## DW_ATOM_die_offset
	.short	6                               ## DW_FORM_data4
	.long	0                               ## Bucket 0
	.long	1                               ## Bucket 1
	.long	2                               ## Bucket 2
	.long	4                               ## Bucket 3
	.long	-1                              ## Bucket 4
	.long	6                               ## Bucket 5
	.long	7                               ## Bucket 6
	.long	-1                              ## Bucket 7
	.long	177616                          ## Hash in Bucket 0
	.long	193444409                       ## Hash in Bucket 1
	.long	177618                          ## Hash in Bucket 2
	.long	383065130                       ## Hash in Bucket 2
	.long	177675                          ## Hash in Bucket 3
	.long	5861387                         ## Hash in Bucket 3
	.long	5861453                         ## Hash in Bucket 5
	.long	5861950                         ## Hash in Bucket 6
.set Lset12, LNames6-Lnames_begin       ## Offset in Bucket 0
	.long	Lset12
.set Lset13, LNames0-Lnames_begin       ## Offset in Bucket 1
	.long	Lset13
.set Lset14, LNames7-Lnames_begin       ## Offset in Bucket 2
	.long	Lset14
.set Lset15, LNames1-Lnames_begin       ## Offset in Bucket 2
	.long	Lset15
.set Lset16, LNames2-Lnames_begin       ## Offset in Bucket 3
	.long	Lset16
.set Lset17, LNames3-Lnames_begin       ## Offset in Bucket 3
	.long	Lset17
.set Lset18, LNames4-Lnames_begin       ## Offset in Bucket 5
	.long	Lset18
.set Lset19, LNames5-Lnames_begin       ## Offset in Bucket 6
	.long	Lset19
LNames6:
	.long	81                              ## +
	.long	1                               ## Num DIEs
	.long	127
	.long	0
LNames0:
	.long	72                              ## <=;
	.long	1                               ## Num DIEs
	.long	97
	.long	0
LNames7:
	.long	76                              ## -
	.long	1                               ## Num DIEs
	.long	108
	.long	0
LNames1:
	.long	88                              ## julia_f_1515
	.long	1                               ## Num DIEs
	.long	72
	.long	0
LNames2:
	.long	86                              ## f
	.long	1                               ## Num DIEs
	.long	72
	.long	0
LNames3:
	.long	83                              ## +;
	.long	2                               ## Num DIEs
	.long	127
	.long	127
	.long	0
LNames4:
	.long	78                              ## -;
	.long	2                               ## Num DIEs
	.long	108
	.long	108
	.long	0
LNames5:
	.long	69                              ## <=
	.long	1                               ## Num DIEs
	.long	97
	.long	0
	.section	__DWARF,__apple_objc,regular,debug
Lobjc_begin:
	.long	1212240712                      ## Header Magic
	.short	1                               ## Header Version
	.short	0                               ## Header Hash Function
	.long	2                               ## Header Bucket Count
	.long	2                               ## Header Hash Count
	.long	12                              ## Header Data Length
	.long	0                               ## HeaderData Die Offset Base
	.long	1                               ## HeaderData Atom Count
	.short	1                               ## DW_ATOM_die_offset
	.short	6                               ## DW_FORM_data4
	.long	-1                              ## Bucket 0
	.long	0                               ## Bucket 1
	.long	5861387                         ## Hash in Bucket 1
	.long	5861453                         ## Hash in Bucket 1
.set Lset20, LObjC0-Lobjc_begin         ## Offset in Bucket 1
	.long	Lset20
.set Lset21, LObjC1-Lobjc_begin         ## Offset in Bucket 1
	.long	Lset21
LObjC0:
	.long	83                              ## +;
	.long	1                               ## Num DIEs
	.long	127
	.long	0
LObjC1:
	.long	78                              ## -;
	.long	1                               ## Num DIEs
	.long	108
	.long	0
	.section	__DWARF,__apple_namespac,regular,debug
Lnamespac_begin:
	.long	1212240712                      ## Header Magic
	.short	1                               ## Header Version
	.short	0                               ## Header Hash Function
	.long	1                               ## Header Bucket Count
	.long	0                               ## Header Hash Count
	.long	12                              ## Header Data Length
	.long	0                               ## HeaderData Die Offset Base
	.long	1                               ## HeaderData Atom Count
	.short	1                               ## DW_ATOM_die_offset
	.short	6                               ## DW_FORM_data4
	.long	-1                              ## Bucket 0
	.section	__DWARF,__apple_types,regular,debug
Ltypes_begin:
	.long	1212240712                      ## Header Magic
	.short	1                               ## Header Version
	.short	0                               ## Header Hash Function
	.long	1                               ## Header Bucket Count
	.long	0                               ## Header Hash Count
	.long	20                              ## Header Data Length
	.long	0                               ## HeaderData Die Offset Base
	.long	3                               ## HeaderData Atom Count
	.short	1                               ## DW_ATOM_die_offset
	.short	6                               ## DW_FORM_data4
	.short	3                               ## DW_ATOM_die_tag
	.short	5                               ## DW_FORM_data2
	.short	4                               ## DW_ATOM_type_flags
	.short	11                              ## DW_FORM_data1
	.long	-1                              ## Bucket 0
	.section	__DWARF,__debug_gnu_pubn,regular,debug
.set Lset22, LpubNames_end0-LpubNames_begin0 ## Length of Public Names Info
	.long	Lset22
LpubNames_begin0:
	.short	2                               ## DWARF Version
.set Lset23, Lcu_begin0-Lsection_info   ## Offset of Compilation Unit Info
	.long	Lset23
	.long	148                             ## Compilation Unit Length
	.long	42                              ## DIE offset
	.byte	48                              ## Attributes: FUNCTION, EXTERNAL
	.asciz	"<=;"                           ## External Name
	.long	62                              ## DIE offset
	.byte	48                              ## Attributes: FUNCTION, EXTERNAL
	.asciz	"+;"                            ## External Name
	.long	72                              ## DIE offset
	.byte	48                              ## Attributes: FUNCTION, EXTERNAL
	.asciz	"f"                             ## External Name
	.long	52                              ## DIE offset
	.byte	48                              ## Attributes: FUNCTION, EXTERNAL
	.asciz	"-;"                            ## External Name
	.long	0                               ## End Mark
LpubNames_end0:
	.section	__DWARF,__debug_gnu_pubt,regular,debug
.set Lset24, LpubTypes_end0-LpubTypes_begin0 ## Length of Public Types Info
	.long	Lset24
LpubTypes_begin0:
	.short	2                               ## DWARF Version
.set Lset25, Lcu_begin0-Lsection_info   ## Offset of Compilation Unit Info
	.long	Lset25
	.long	148                             ## Compilation Unit Length
	.long	0                               ## End Mark
LpubTypes_end0:
.subsections_via_symbols
	.section	__DWARF,__debug_line,regular,debug
Lsection_line:
Lline_table_start0:
