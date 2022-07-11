
-- registrations
select top 100
	pd.paper_deed_id as id,
	'registration' as 'type',
	1 as 'version',
	1 as 'is_active',
	'registered' as 'global_state',
	'promoted' as 'state',
	pd.deed_date as 'document_date',
	pd.request_date as 'registration_date',
	pd.created_on as 'publication_date',
	pd.updated_on as 'last_modification_date',
	'' as justification,
	pd.dossier_reference as 'dossier_reference',
	pd.repertorium_number as 'repertory_number',
	'TODO' as 'registrant_id'
from crt.paper_deed pd

-- legal acts
select top 100
	jd.juridical_deed_id as id,
	'legal_act' as 'type',
	jd.paper_deed_id as 'registration_id',
	jd.juridical_deed_number as 'reference',
	jd.registration_type_id as 'legal_act_type_id',
	lat.definition as definition,
	null as deleted_at


from crt.juridical_deed jd
inner join crt.registration_type lat
	on lat.registration_type_id = jd.registration_type_id


	select top 10 * from crt.juridical_deed
