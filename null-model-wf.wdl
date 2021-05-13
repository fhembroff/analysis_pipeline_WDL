version 1.0

# [1] null_model_r
task null_model_r {
	input {
		String? output_prefix
		String outcome
		File phenotype_file
		Array[File]? gds_files
		File? pca_file
		File? related_matrix_file
		File? family
		File? conditional_variant_file
		Array[File]? covars
		File? group_var
		File? inverse_normal
		Int? n_pcs
		Int? rescale_variance
		Int? resid_covars
		File? sample_include_file
		File? norm_bygroup
		# runtime attributes
		Int addldisk = 1
		Int cpu = 2
		Int memory = 4
		Int preempt = 3
	}
	command <<<
		set -eux -o pipefail

		echo "Generating config file"
		python << CODE
		import os
		f = open("null_model.config", "a")
		if "~{output_prefix}" != "":
			filename = "~{output_prefix}_null_model"
			f.write('out_prefix "' + filename + '"\n')
			phenotype_filename = "~{output_prefix}_phenotypes.RData"
			f.write('out_phenotype_file"' + phenotype_filename + '"\n')
		}
		else{
			f.write('out_prefix "null_model"')
			f.write('out_phenotype_file "phenotypes.RData"')
		}

		f.write('outcome ~{outcome}')
		f.write('phenotype_file ~{phenotype_file}')
		if "~{isDefinedGDS}" == "true":  # double check this isn't supposed to be True
			def split_n_space(py_splitstring):
			# Return [file name with chr name replaced by space, chr name]
			# Ex: test_data_chrX.gdsreturns ["test_data_chr .gds", "X"]
				if(unicode(str(py_splitstring[1][1])).isnumeric()):
					# chr10 and above
					py_thisVcfWithSpace = "".join([
						py_splitstring[0],
						"chr ",
						py_splitstring[1][2:]])
					py_thisChr = py_splitstring[1][0:2]
				else:
					# chr9 and below + chrX
					py_thisVcfWithSpace = "".join([
						py_splitstring[0],
						"chr ",
						py_splitstring[1][1:]])
					py_thisChr = py_splitstring[1][0:1]
				return [py_thisVcfWithSpace, py_thisChr]

			py_gds_array = ['~{sep="','" gds_files}']
			gds = py_gds_array[0]
			py_splitup = split_n_space(gds)[0]
			chr = split_n_space(gds)[1]
			f.write('gds_file "' + py_splitup + chr + '"')

			 
		############
		  }
		  if(inputs.pca_file){
			  arguments.push('pca_file "' + inputs.pca_file.path + '"')
		  }
		  if(inputs.relatedness_matrix_file){
			  arguments.push('relatedness_matrix_file "' + inputs.relatedness_matrix_file.path + '"')
		  }
		  if(inputs.family){
			  arguments.push('family ' + inputs.family)
		  }
		  if(inputs.conditional_variant_file){
			  arguments.push('conditional_variant_file "' + inputs.conditional_variant_file.path + '"')
		  }
		  if(inputs.covars){
			  temp = []
			  for(var i=0; i<inputs.covars.length; i++){
				  temp.push(inputs.covars[i])
			  }
			  arguments.push('covars "' + temp.join(' ') + '"')
		  }
		  if(inputs.group_var){
			  arguments.push('group_var "' + inputs.group_var + '"')
		  }
		  if(inputs.inverse_normal){
			  arguments.push('inverse_normal ' + inputs.inverse_normal)
		  }
		  if(inputs.n_pcs){
			  if(inputs.n_pcs > 0)
				  arguments.push('n_pcs ' + inputs.n_pcs)
		  }
		  if(inputs.rescale_variance){
			  arguments.push('rescale_variance "' + inputs.rescale_variance + '"')
		  }
		  if(inputs.resid_covars){
			  arguments.push('resid_covars ' + inputs.resid_covars)
		  }
		  if(inputs.sample_include_file){
			  arguments.push('sample_include_file "' + inputs.sample_include_file.path + '"')
		  }
		  if(inputs.norm_bygroup){
			  arguments.push('norm_bygroup ' + inputs.norm_bygroup)
		  }
		f.close()
		exit()
		CODE

		echo "Calling R script null_model.R"
		Rscript /usr/local/analysis_pipeline/R/null_model.R null_model.config
	>>>
	
	# Estimate disk size required
	Int phenotype_size = ceil(size(phenotype_file, "GB"))
	# other files, etc
	Int finalDiskSize = phenotype_size + addldisk

	# Workaround
	Boolean isDefinedGDS = defined(gds_files)
	
	runtime {
		cpu: cpu
		docker: "uwgac/topmed-master:2.10.0"
		disks: "local-disk " + finalDiskSize + " HDD"
		memory: "${memory} GB"
		preemptibles: "${preempt}"
	}
	output {
		File null_model_output = output_file_name
		File config_file = "vcf2gds.config"
	}
}

# [2] null_model_report
task null_model_report {
	input {
		Array[File] gdss
		# runtime attr
		Int addldisk = 1
		Int cpu = 2
		Int memory = 4
		Int preempt = 2
	}
	command <<<
		set -eux -o pipefail

		# This is a workaround for the Python code to work correctly
		# Symlinks would be preferable, but they do not work on GCS
		echo "Copying inputs into the workdir"
		BASH_FILES=(~{sep=" " gdss})
		for BASH_FILE in ${BASH_FILES[@]};
		do
			cp ${BASH_FILE} .
		done

		echo "Generating config file"
		python << CODE
		import os

		def find_chromosome(file):
			chr_array = []
			chrom_num = split_on_chromosome(file)
			if(unicode(str(chrom_num[1][1])).isnumeric()):
				# two digit number
				chr_array.append(chrom_num[1][0])
				chr_array.append(chrom_num[1][1])
			else:
				# one digit number or Y/X/M
				chr_array.append(chrom_num[1][0])
			return "".join(chr_array)

		def split_on_chromosome(file):
			# if input is "amishchr1.gds"
			# output is ["amish", ".gds", "chr"]
			chrom_num = file
			if "chr" in chrom_num:
				chrom_num = chrom_num.split("chr")
				chrom_num.append("chr")
			else:
				return "error-invalid-inputs"
			return chrom_num

		def write_config(chr_array, precisely_one_gds_split):
			f = open("unique_variant_ids.config", "a")
			f.write("chromosomes ")
			f.write("'")
			for chr in chr_array:
				f.write(chr)
				f.write(" ")
			f.write("'")
			f.write("\ngds_file ")
			f.write("'")
			f.write(precisely_one_gds_split[0])  # first part
			f.write(precisely_one_gds_split[2])  # string "chr"
			f.write(" ")  # space where R script inserts chr number
			if(unicode(str(precisely_one_gds_split[1][1])).isnumeric()):
				# two digit number
				f.write(precisely_one_gds_split[1][2:])
			else:
				# one digit number or Y/X/M
				f.write(precisely_one_gds_split[1][1:])
			f.write("'")
			f.close()

		gds_array_fullpath = ['~{sep="','" gdss}']
		gds_array_basenames = []
		for fullpath in gds_array_fullpath:
			gds_array_basenames.append(os.path.basename(fullpath))

		# make list of all chromosomes found in input files
		chr_array = []
		for gds_file in gds_array_basenames:
			this_chr = find_chromosome(gds_file)
			if this_chr == "error-invalid-inputs":
				print("Unable to determine chromosome number from inputs.")
				print("Please ensure your files contain ''chr'' followed by")
				print("the number of letter of the chromosome (chr1, chr2, etc)")
				exit(1)
			else:
				chr_array.append(this_chr)
		
		# assuming all gds files have same pattern in filename, any one will do
		one_valid_gds_split = split_on_chromosome(gds_array_basenames[0])
		write_config(chr_array, one_valid_gds_split)
		CODE
		
		echo "Calling uniqueVariantIDs.R"
		Rscript /usr/local/analysis_pipeline/R/unique_variant_ids.R unique_variant_ids.config
	>>>
	# Estimate disk size required
	Int gdss_size = ceil(size(gdss, "GB"))
	Int finalDiskSize = 2*gdss_size + addldisk

	runtime {
		cpu: cpu
		docker: "uwgac/topmed-master:2.10.0"
		disks: "local-disk " + finalDiskSize + " HDD"
		memory: "${memory} GB"
		preemptibles: "${preempt}"
	}
	output {
		Array[File] null_model_report_output = glob("*.html")
	}
}

workflow e_nullmodel {
	input {
		Array[File] vcf_files
		Array[String] format = ["GT"]
		Boolean check_gds = false
	}

	scatter(vcf_file in vcf_files) {
		call vcf2gds {
			input:
				vcf = vcf_file,
				format = format
		}
	}
	
	call unique_variant_id {
		input:
			gdss = vcf2gds.gds_output,
	}
	
	if(check_gds) {
		scatter(gds in unique_variant_id.unique_variant_id_gds_per_chr) {
			call check_gds {
				input:
					gds = gds,
					vcfs = vcf_files
			}
		}
	}

	meta {
		author: "Ash O'Farrell"
		email: "aofarrel@ucsc.edu"
	}
}
