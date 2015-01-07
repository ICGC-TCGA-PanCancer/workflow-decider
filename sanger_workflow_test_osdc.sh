perl bin/sanger_workflow_decider.pl \
--schedule-force-run \
--seqware-clusters conf/cluster.json \
--workflow-version 1.0.1 \
--bwa-workflow-version 2.6.0 \
--working-dir osdc \
--gnos-url  https://gtrepo-osdc-icgc.annailabs.com \
--decider-config conf/decider.ini \
--use-cached-xml \
--workflow-skip-scheduling
#--schedule-whitelist-donor donors_I_want.txt \

#https://gtrepo-etri.annailabs.com  \
#https://gtrepo-osdc-icgc.annailabs.com
