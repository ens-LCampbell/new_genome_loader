=head1 LICENSE

Copyright [1999-2014] EMBL-European Bioinformatics Institute
and Wellcome Trust Sanger Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


=pod

=head1 NAME

Bio::EnsEMBL::Pipeline::PipeConfig::LoadGFF3_conf

=head1 DESCRIPTION

Load a valid GFF3 file into a core database.

=head1 Author

James Allen

=cut

package Bio::EnsEMBL::Pipeline::PipeConfig::LoadGFF3_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Pipeline::PipeConfig::EGGeneric_conf');

use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;
use Bio::EnsEMBL::Hive::Version 2.4;

use File::Spec::Functions qw(catdir);

sub default_options {
  my ($self) = @_;
  return {
    %{$self->default_options_generic},
    
    pipeline_name => 'load_gff3_'.$self->o('species'),
    
    gff3_tidy_file => $self->o('gff3_file').'.tidied',
    fasta_file     => catdir($self->o('pipeline_dir'), $self->o('species').'.fa'),
    
    # If loading data from NCBI, their homology- and transcriptome-based
    # gene model modifications can be loaded as sequence edits in the db.
    genbank_file => undef,
    
    # Sometimes selenocysteines and readthrough stop codons are only
    # indicated in the provider's protein sequences.
    protein_fasta_file => undef,
    
    biotype_report_filename => undef,
    seq_edit_tt_report_filename => undef,
    seq_edit_tn_report_filename => undef,
    protein_seq_report_filename => undef,
    protein_seq_fixes_filename => undef,
  };
}

sub default_options_generic {
  my ($self) = @_;
  return {
    %{$self->SUPER::default_options},
    
    # Attempt to correct transcripts with invalid translations.
    fix_models => 1,
    
    # Where fixes fail, apply seq-edits where possible.
    apply_seq_edits => 1,
    
    # Can also load genes into an otherfeatures db.
    db_type => 'core',
    
    # This logic_name will almost certainly need to be changed, so
    # that a customised description can be associated with the analysis.
    logic_name      => 'gff3_genes',
    analysis_module => 'Bio::EnsEMBL::Pipeline::Runnable::EG::LoadGFF3::LoadGFF3',
    
    # When adding seq_region synonyms, an external_db is required.
    # This should ideally be something less generic, e.g. RefSeq_genomic.
    synonym_external_db => 'ensembl_internal_synonym',
    
    # Remove existing genes; if => 0 then existing analyses
    # and their features will remain, with the logic_name suffixed by '_bkp'.
    delete_existing => 1,
    
    # Retrieve analysis descriptions from the production database;
    # the supplied registry file will need the relevant server details.
    production_lookup => 1,
    
    # Validate GFF3 before trying to parse it.
    gt_exe        => 'gt',
    gff3_tidy     => $self->o('gt_exe').' gff3 -tidy -sort -retainids',
    gff3_validate => $self->o('gt_exe').' gff3validator',
    
    # Remove any extra gubbins from the Fasta ID.
    fasta_subst => 's/^(>[^\|]+).*/$1/',
    fasta_tidy  => "perl -i -pe '".$self->o('fasta_subst')."'",
    
    # Lists of the types that we expect to see in the GFF3 file.
    gene_types   => ['gene', 'pseudogene', 'miRNA_gene', 'ncRNA_gene',
                     'rRNA_gene', 'snoRNA_gene', 'snRNA_gene', 'tRNA_gene' ],
    mrna_types   => ['mRNA', 'transcript', 'pseudogenic_transcript',
                     'pseudogenic_rRNA', 'pseudogenic_tRNA',
                     'ncRNA', 'lincRNA', 'lncRNA', 'miRNA', 'pre_miRNA',
                     'RNase_MRP_RNA', 'RNAse_P_RNA', 'rRNA', 'snoRNA',
                     'snRNA', 'sRNA', 'SRP_RNA', 'tRNA'],
    exon_types   => ['exon', 'pseudogenic_exon'],
    cds_types    => ['CDS'],
    utr_types    => ['five_prime_UTR', 'three_prime_UTR'],
    ignore_types => ['misc_RNA', 'RNA', 'intron',
                     'match', 'match_part',
                     'cDNA_match', 'nucleotide_match', 'protein_match',
                     'polypeptide', 'protein',
                     'chromosome', 'supercontig', 'contig',
                     'region', 'biological_region',
                     'regulatory_region', 'repeat_region'],
    
    # By default, it is assumed that the above type lists are exhaustive.
    # If there is a type in the GFF3 that is not listed, an error will be
    # thrown, unless 'types_complete' = 0.
    types_complete => 1,
    
    # By default, load the GFF3 "ID" fields as stable_ids, and ignore "Name"
    # fields. If they exist, can load them as stable IDs instead, with the
    # value 'stable_id'; or load them as xrefs by setting to 'xref'.
    use_name_field => undef,
    
    # When adding "Name" fields as xrefs, external_dbs are required.
    xref_gene_external_db        => undef, # e.g. RefSeq_gene_name
    xref_transcript_external_db  => undef, # e.g. RefSeq_mRNA
    xref_translation_external_db => undef, # e.g. RefSeq_peptide
    
    # If there are polypeptide rows in the GFF3, defined by 'Derives_from'
    # relationships, those will be used to determine the translation
    # (rather than inferring from CDS), unless 'polypeptides' = 0. 
    polypeptides => 1,
    
    # Some sources (I'm looking at you, RefSeq) have 1- or 2-base introns
    # defined to deal with readthrough stop codons. But their sequence
    # files contradict this, and include those intronic bases. The NCBI
    # .gbff files then define a 1- or 2-base insertion of 'N's, which
    # fixes everything up (and which this pipeline can handle).
    # So, the pipeline can merge exons that are separated by a small intron.
    min_intron_size => undef,
    
    # Set the biotype for transcripts that produce invalid translations. We
    # can treat them as pseudogenes by setting 'nontranslating' => "pseudogene".
    # The default is "nontranslating_CDS", and in this case the translation
    # is still added to the core db, on the assumption that remedial action
    # will fix it (i.e. via the ApplySeqEdits module).
    nontranslating => 'nontranslating_CDS',
    
    # By default, genes are loaded as full-on genes; load instead as a
    # predicted transcript by setting 'prediction' = 1.
    prediction => 0,
    
    # Big genomes need more memory, because we need to load all the
    # sequence into an in-memory database.
    big_genome_threshold => 1e9,
  };
}

sub beekeeper_extra_cmdline_options {
  my ($self) = @_;

  my $options = join(' ',
    $self->SUPER::beekeeper_extra_cmdline_options,
    "-reg_conf ".$self->o('registry')
  );

  return $options;
}

sub hive_meta_table {
  my ($self) = @_;

  return {
    %{$self->SUPER::hive_meta_table},
    'hive_use_param_stack'  => 1,
  };
}

sub pipeline_create_commands {
  my ($self) = @_;

  return [
    @{$self->SUPER::pipeline_create_commands},
    'mkdir -p '.$self->o('pipeline_dir'),
  ];
}

sub pipeline_wide_parameters {
  my ($self) = @_;
  
  return {
    %{$self->pipeline_wide_parameters_generic},
    'species'            => $self->o('species'),
    'gff3_file'          => $self->o('gff3_file'),
    'gff3_tidy_file'     => $self->o('gff3_tidy_file'),
    'fasta_file'         => $self->o('fasta_file'),
    'genbank_file'       => $self->o('genbank_file'),
    'protein_fasta_file' => $self->o('protein_fasta_file'),

    'biotype_report_filename'     => $self->o('biotype_report_filename'),
    'seq_edit_tt_report_filename' => $self->o('seq_edit_tt_report_filename'),
    'seq_edit_tn_report_filename' => $self->o('seq_edit_tn_report_filename'),
    'protein_seq_report_filename' => $self->o('protein_seq_report_filename'),
    'protein_seq_fixes_filename'  => $self->o('protein_seq_fixes_filename'),
  };
}

sub pipeline_wide_parameters_generic {
  my ($self) = @_;
  
  return {
    %{$self->SUPER::pipeline_wide_parameters},
    'db_type'              => $self->o('db_type'),
    'logic_name'           => $self->o('logic_name'),
    'delete_existing'      => $self->o('delete_existing'),
    'fix_models'           => $self->o('fix_models'),
    'apply_seq_edits'      => $self->o('apply_seq_edits'),
    'big_genome_threshold' => $self->o('big_genome_threshold'),
  };
}

sub pipeline_analyses {
  my ($self) = @_;
  
  return [
    {
      -logic_name      => 'RunPipeline',
      -module          => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
      -max_retry_count => 0,
      -input_ids       => [ {} ],
      -flow_into       => ['GFF3Tidy'],
      -meadow_type     => 'LOCAL',
    },
    
    @{ $self->pipeline_analyses_generic}
  ];
}

sub pipeline_analyses_generic {
  my ($self) = @_;
  
  return [
    {
      -logic_name        => 'GFF3Tidy',
      -module            => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
      -max_retry_count   => 0,
      -parameters        => {
                              cmd => $self->o('gff3_tidy').' #gff3_file# > #gff3_tidy_file#',
                            },
      -rc_name           => 'normal',
      -flow_into         => ['GFF3Validate'],
    },

    {
      -logic_name        => 'GFF3Validate',
      -module            => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
      -max_retry_count   => 0,
      -parameters        => {
                              cmd => $self->o('gff3_validate').' #gff3_tidy_file#',
                            },
      -rc_name           => 'normal',
      -flow_into         => {
                              '1' => WHEN('-e #fasta_file#' =>
                                      ['FastaTidy'],
                                     ELSE
                                      ['DumpGenome']),
                            },
    },

    {
      -logic_name        => 'FastaTidy',
      -module            => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
      -max_retry_count   => 1,
      -parameters        => {
                              cmd => $self->o('fasta_tidy').' #fasta_file#',
                            },
      -rc_name           => 'normal',
      -flow_into         => ['BackupDatabase'],
    },

    {
      -logic_name        => 'DumpGenome',
      -module            => 'Bio::EnsEMBL::Pipeline::Runnable::EG::Common::RunnableDB::DumpGenome',
      -analysis_capacity => 10,
      -max_retry_count   => 1,
      -parameters        => {
                              genome_file  => '#fasta_file#',
                              header_style => 'name',
                            },
      -rc_name           => 'normal',
      -flow_into         => ['BackupDatabase'],
    },

    {
      -logic_name        => 'BackupDatabase',
      -module            => 'Bio::EnsEMBL::Pipeline::Runnable::EG::Common::RunnableDB::DatabaseDumper',
      -analysis_capacity => 10,
      -max_retry_count   => 1,
      -parameters        => {
                              output_file => catdir($self->o('pipeline_dir'), '#species#', 'pre_gff3_bkp.sql.gz'),
                            },
      -rc_name           => 'normal',
      -flow_into         => {
                              '1' => WHEN('#delete_existing#' =>
                                      ['DeleteGenes'],
                                     ELSE
                                      ['AnalysisSetup']),
                            },
    },

    {
      -logic_name        => 'DeleteGenes',
      -module            => 'Bio::EnsEMBL::Pipeline::Runnable::EG::LoadGFF3::DeleteGenes',
      -analysis_capacity => 10,
      -max_retry_count   => 1,
      -parameters        => {},
      -rc_name           => 'normal',
      -flow_into         => ['AnalysisSetup'],
    },

    {
      -logic_name        => 'AnalysisSetup',
      -module            => 'Bio::EnsEMBL::Pipeline::Runnable::EG::Common::RunnableDB::AnalysisSetup',
      -analysis_capacity => 10,
      -max_retry_count   => 0,
      -parameters        => {
                              db_backup_required => 1,
                              db_backup_file     => catdir($self->o('pipeline_dir'), '#species#', 'pre_gff3_bkp.sql.gz'),
                              module             => $self->o('analysis_module'),
                              delete_existing    => $self->o('delete_existing'),
                              production_lookup  => $self->o('production_lookup'),
                              production_db      => $self->o('production_db'),
                            },
      -meadow_type       => 'LOCAL',
      -flow_into         => WHEN('-s #fasta_file# < #big_genome_threshold#' =>
                              ['AddSynonyms'],
                            ELSE
                              ['AddSynonyms_HighMem']),
    },

    {
      -logic_name        => 'AddSynonyms',
      -module            => 'Bio::EnsEMBL::Pipeline::Runnable::EG::LoadGFF3::AddSynonyms',
      -analysis_capacity => 10,
      -max_retry_count   => 0,
      -parameters        => {
                              escape_branch       => -1,
                              synonym_external_db => $self->o('synonym_external_db'),
                            },
      -rc_name           => 'normal',
      -flow_into         => {
                               '1' => ['LoadGFF3'],
                              '-1' => ['AddSynonyms_HighMem'],
                            },
    },

    {
      -logic_name        => 'AddSynonyms_HighMem',
      -module            => 'Bio::EnsEMBL::Pipeline::Runnable::EG::LoadGFF3::AddSynonyms',
      -analysis_capacity => 10,
      -max_retry_count   => 0,
      -parameters        => {
                              synonym_external_db => $self->o('synonym_external_db'),
                            },
      -rc_name           => '8Gb_mem',
      -flow_into         => ['LoadGFF3_HighMem'],
    },

    {
      -logic_name        => 'LoadGFF3',
      -module            => 'Bio::EnsEMBL::Pipeline::Runnable::EG::LoadGFF3::LoadGFF3',
      -analysis_capacity => 10,
      -max_retry_count   => 0,
      -parameters        => {
                              escape_branch   => -1,
                              gene_source     => $self->o('gene_source'),
                              gff3_file       => '#gff3_tidy_file#',
                              gene_types      => $self->o('gene_types'),
                              mrna_types      => $self->o('mrna_types'),
                              exon_types      => $self->o('exon_types'),
                              cds_types       => $self->o('cds_types'),
                              utr_types       => $self->o('utr_types'),
                              ignore_types    => $self->o('ignore_types'),
                              types_complete  => $self->o('types_complete'),
                              use_name_field  => $self->o('use_name_field'),
                              polypeptides    => $self->o('polypeptides'),
                              min_intron_size => $self->o('min_intron_size'),
                              nontranslating  => $self->o('nontranslating'),
                              prediction      => $self->o('prediction'),
                              xref_gene_external_db        => $self->o('xref_gene_external_db'),
                              xref_transcript_external_db  => $self->o('xref_transcript_external_db'),
                              xref_translation_external_db => $self->o('xref_translation_external_db'),
                              
                            },
      -rc_name           => '8Gb_mem',
      -flow_into         => {
                               '1' => WHEN('#fix_models#' =>
                                        ['FixModels'],
                                      ELSE
                                        ['EmailReport']),
                              '-1' => ['LoadGFF3_HighMem'],
                            },
    },

    {
      -logic_name        => 'LoadGFF3_HighMem',
      -module            => 'Bio::EnsEMBL::Pipeline::Runnable::EG::LoadGFF3::LoadGFF3',
      -analysis_capacity => 10,
      -max_retry_count   => 0,
      -parameters        => {
                              gene_source     => $self->o('gene_source'),
                              gff3_file       => '#gff3_tidy_file#',
                              gene_types      => $self->o('gene_types'),
                              mrna_types      => $self->o('mrna_types'),
                              exon_types      => $self->o('exon_types'),
                              cds_types       => $self->o('cds_types'),
                              utr_types       => $self->o('utr_types'),
                              ignore_types    => $self->o('ignore_types'),
                              types_complete  => $self->o('types_complete'),
                              use_name_field  => $self->o('use_name_field'),
                              polypeptides    => $self->o('polypeptides'),
                              min_intron_size => $self->o('min_intron_size'),
                              nontranslating  => $self->o('nontranslating'),
                              prediction      => $self->o('prediction'),
                              xref_gene_external_db        => $self->o('xref_gene_external_db'),
                              xref_transcript_external_db  => $self->o('xref_transcript_external_db'),
                              xref_translation_external_db => $self->o('xref_translation_external_db'),
                              
                            },
      -rc_name           => '16Gb_mem',
      -flow_into         => {
                              '1' => WHEN('#fix_models#' =>
                                      ['FixModels'],
                                     ELSE
                                      ['EmailReport']),
                            },
    },

    {
      -logic_name        => 'FixModels',
      -module            => 'Bio::EnsEMBL::Pipeline::Runnable::EG::LoadGFF3::FixModels',
      -analysis_capacity => 10,
      -max_retry_count   => 0,
      -parameters        => {},
      -rc_name           => 'normal',
      -flow_into         => {
                              '1' => WHEN('#apply_seq_edits#' =>
                                      ['ApplySeqEdits'],
                                     ELSE
                                      ['EmailReport']),
                            },
    },

    {
      -logic_name        => 'ApplySeqEdits',
      -module            => 'Bio::EnsEMBL::Pipeline::Runnable::EG::LoadGFF3::ApplySeqEdits',
      -analysis_capacity => 10,
      -max_retry_count   => 0,
      -parameters        => {},
      -rc_name           => 'normal',
      -flow_into         => ['EmailReport'],
    },

    {
      -logic_name        => 'EmailReport',
      -module            => 'Bio::EnsEMBL::Pipeline::Runnable::EG::LoadGFF3::EmailReport',
      -max_retry_count   => 1,
      -parameters        => {
                              email   => $self->o('email'),
                              subject => 'GFF3 Loading pipeline has completed for #species#',
                            },
      -rc_name           => 'normal',
    },

  ];
}

1;
