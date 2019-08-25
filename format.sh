#!/bin/bash

dfmt \
	--end_of_line=lf \
	--indent_style=tab \
    	--brace_style=otbs \
     	--align_switch_statements=true \
     	--split_operator_at_line_end=false \
	--soft_max_line_length=80 \
     	--max_line_length=100 \
	--space_after_cast=true \
	--compact_labeled_statements=true \
	--template_constraint_style=conditional_newline_indent \
	--space_before_aa_colon=false \
     	-i .
