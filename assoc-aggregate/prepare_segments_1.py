#~{segments_file}
IIsegments_fileII = "_test-data-and-truths_/assoc/segments.txt"

# ['~{sep="','" input_gds_files}']
IIinput_gds_filesII = ["_test-data-and-truths_/assoc/1KG_phase3_subset_chr1.gds", "_test-data-and-truths_/gds/a_vcf2gds/1KG_phase3_subset_chr2_butwithadifferentname.gds"]

#['~{sep="','" variant_include_files}']
IIvariant_include_filesII = [""]

#['~{sep="','" aggregate_files}']
IIaggregate_filesII = ["_test-data-and-truths_/assoc/aggregate_list_chr1.RData", "_test-data-and-truths_/assoc/aggregate_list_chr2.RData"]

from zipfile import ZipFile

def find_chromosome(file):
	chr_array = []
	chrom_num = split_on_chromosome(file)
	if len(chrom_num) == 1:
		acceptable_chrs = [str(integer) for integer in list(range(1,22))]
		acceptable_chrs.extend(["X","Y","M"])
		print(acceptable_chrs)
		print(type(chrom_num))
		if chrom_num in acceptable_chrs:
			return chrom_num
		else:
			print("%s appears to be an invalid chromosome number." % chrom_num)
			exit(1)
	elif (unicode(str(chrom_num[1])).isnumeric()):
		# two digit number
		chr_array.append(chrom_num[0])
		chr_array.append(chrom_num[1])
	else:
		# one digit number or Y/X/M
		chr_array.append(chrom_num[0])
	return "".join(chr_array)

def split_on_chromosome(file):
	chrom_num = file.split("chr")[1]
	return chrom_num

def pair_chromosome_gds(file_array):
	gdss = dict() # forced to use constructor due to WDL syntax issues
	for i in range(0, len(file_array)-1):
		# Key is chr number, value is associated GDS file
		gdss[int(find_chromosome(file_array[i]))] = file_array[i]
		i += 1
	return gdss

def pair_chromosome_gds_special(file_array, agg_file):
	gdss = dict()
	for i in range(0, len(file_array)-1):
		gdss[int(find_chromosome(file_array[i]))] = agg_file
	return gdss

def wdl_get_segments():
	segfile = open(IIsegments_fileII, 'rb')
	segments = str((segfile.read(64000))).split('\n') # var segments = self[0].contents.split('\n');
	segfile.close()
	segments = segments[1:] # segments = segments.slice(1) # cut off the first lineF
	return segments

# Prepare GDS output
input_gdss = pair_chromosome_gds(IIinput_gds_filesII)
output_gdss = []
gds_segments = wdl_get_segments()
for i in range(0, len(gds_segments)):
	try:
		chr = int(gds_segments[i].split('\t')[0])
	except ValueError: # chr X, Y, M
		chr = gds_segments[i].split('\t')[0]
	if(chr in input_gdss):
		output_gdss.append(input_gdss[chr])
gds_output_hack = open("gds_output_debug.txt", "a")
gds_output_hack.writelines(["%s " % thing for thing in output_gdss])
gds_output_hack.close()

# Prepare segment output
input_gdss = pair_chromosome_gds(IIinput_gds_filesII)
output_segments = []
actual_segments = wdl_get_segments()
for i in range(0, len(actual_segments)):
	try:
		chr = int(actual_segments[i].split('\t')[0])
	except ValueError: # chr X, Y, M
		chr = actual_segments[i].split('\t')[0]
	if(chr in input_gdss):
		output_segments.append(i+1)
if max(output_segments) != len(output_segments): # I don't know if this case is actually problematic but I suspect it will be.
	print("ERROR: Subsequent code relies on output_segments being a list of consecutive integers.")
	print("Debug information: Max of list is %s, len of list is %s" % [max(output_segments), len(output_segments)])
	print("Debug information: List is as follows:\n\t%s" % output_segments)
	exit(1)
for j in range(0, len(output_segments)):
	dummy = open("%s.integer" % j, "a")
segs_output_hack = open("segs_output_debug.txt", "a")
segs_output_hack.writelines(["%s " % thing for thing in output_segments])
segs_output_hack.close()

# Prepare aggregate output
input_gdss = pair_chromosome_gds(IIinput_gds_filesII)
agg_segments = wdl_get_segments()
if 'chr' in os.path.basename(IIaggregate_filesII[0]):
	input_aggregate_files = pair_chromosome_gds(IIaggregate_filesII)
else:
	input_aggregate_files = pair_chromosome_gds_special(IIinput_gds_filesII, IIaggregate_filesII[0])
output_aggregate_files = []
for i in range(0, len(segments)-1):
	chr = segments[i].split('\t')[0]
	if(chr in input_aggregate_files):
		output_aggregate_files.append(input_aggregate_files[chr])
	else if (chr in input_gdss):
		output_aggregate_files.append(None)

# Prepare variant include output
input_gdss = pair_chromosome_gds(IIinput_gds_filesII)
var_segments = wdl_get_segments()
if IIvariant_include_filesII != [""]:
	input_variant_files = pair_chromosome_gds(IIvariant_include_filesII)
	output_variant_files = []
	for i in range(0, len(var_segments)):
		try:
			chr = int(var_segments[i].split('\t')[0])
		except ValueError: # chr X, Y, M
			chr = var_segments[i].split('\t')[0]
		if(chr in input_variant_files):
			output_variant_files.append(input_variant_files[chr])
		elif(chr in input_gdss):
			output_variant_files.append(None)
		else:
			pass
else:
	null_outputs = []
	for i in range(0, len(var_segments)):
		try:
			chr = int(var_segments[i].split('\t')[0])
		except ValueError: # chr X, Y, M
			chr = var_segments[i].split('\t')[0]
		if(chr in input_gdss):
			null_outputs.append(None)
	output_variant_files = null_outputs # need the same name as if/else for outputs is iffy in wdl, although file hack may make this unneeded
var_output_hack = open("variant_output_debug.txt", "a")
var_output_hack.writelines(["%s " % thing for thing in output_variant_files])
var_output_hack.close()

# Make a bunch of zip files
for i in range(0, max(output_segments)):
	this_zip = ZipFile("dotprod%s.zip" % i, "w")
	this_zip.write("%s" % output_gdss[i])
	this_zip.write("%s.integer" % output_segments[i])
	this_zip.write("%s" % output_aggregate_files[i])
	this_zip.close()