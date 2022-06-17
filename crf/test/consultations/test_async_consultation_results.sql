

declare @consultationNumber varchar(50) = 'CRF-R-2022061730003' -- when <null> or empty string, we will get the last created consultation automatically.
declare @previousPersonNrns varchar(100) = '' -- add previous nrns from the consulted person here, when applicable (use pipe character as glue)
declare @previousPartnerNrns varchar(100) = '' -- add previous nrns from the partner here, when applicable (use pipe character as glue)

-------------------------------------------------------------------------------------------------------------------------------------------------------------
--                                                                                                                                                         --
--   D O   N O T   A L T E R   S C R I P T   B E L O W                                                                                                     --
--                                                                                                                                                         --
-------------------------------------------------------------------------------------------------------------------------------------------------------------

declare @errorCount int = 0

if @consultationNumber is null or len(@consultationNumber) < 1
begin
	select @consultationNumber = consultation_number
	from crt.consultation
	where consultation_id = (select max(consultation_id) from crt.consultation)
end 

set nocount on
print '      ******************************************************************************************'
print '      *                                                                                        *'
print '      *  TEST REPORT CONSULTATION                                                              *'
print '      *                                                                                        *'
print '      ******************************************************************************************'
print ''
print '         Consultation Number          : ' + convert(varchar(50), @consultationNumber)
print '         Date and time                : ' + convert(varchar(50), getdate())
print ''

SELECT 
    value as nrn
into #previousPersonNrns
FROM 
    STRING_SPLIT(@previousPersonNrns, '|')
where len(value) > 0

SELECT 
    value as nrn
into #previousPartnerNrns
FROM 
    STRING_SPLIT(@previousPartnerNrns, '|')
where len(value) > 0

select r.*
into #consultedRegisters
from crt.consultation c
inner join crt.consultation_register_type cr
	on cr.consultation_id = c.consultation_id
inner join crt.register_type r
	on r.register_type_id = cr.register_type_id
where c.consultation_number = @consultationNumber


DECLARE c CURSOR FOR 
SELECT r.register_name, r.name_nl
FROM #consultedRegisters r

declare @register_name varchar(20)
declare @register_name_nl varchar(50)
declare @tempLoop int = 0

OPEN c  
FETCH NEXT FROM c INTO @register_name, @register_name_nl 

WHILE @@FETCH_STATUS = 0  
BEGIN  
	
      print '         ' + case when @tempLoop = 0 then 'Registers                    : ' else '                               ' end + @register_name + ' - ' + @register_name_nl 
	  set @tempLoop = @tempLoop + 1
	  FETCH NEXT FROM c INTO @register_name, @register_name_nl 
END 

CLOSE c  
DEALLOCATE c 

print ''

declare @consultationState varchar(20)
declare @dossierContextId int
declare @dossierContextName varchar(50)
declare @consultationResultCount int
declare @consultationPersonState varchar(20)
declare @consultationCanBeTested int
declare @personNRN varchar(11)
declare @partnerNRN varchar(11)

select @consultationState = c.state 
	, @dossierContextId = c.dossier_context_id
	, @dossierContextName = dc.name_nl
	, @consultationResultCount = 0 -- TODO: add result count here
	, @consultationPersonState = 
		case 
			when arert_incoming.external_register_consultation_request_id is not null then 'DECEASED'
			when p.is_deceased = 1 then 'DECEASED' 
			when c.death_certificate_document_id is not null then 'DECEASED'
			else 'ALIVE'
		end
	, @consultationCanBeTested = 
		case 
			when p.person_id is null then 0
			else 1
		end
	, @personNRN = p.nrn
	, @partnerNRN = pp.nrn
from crt.consultation c
left join crt.dossier_context dc
	on dc.dossier_context_id = c.dossier_context_id
left join crt.consultation_requester cr
	on cr.requester_id = c.requester_id
left join ext.external_register_consultation_request arert_incoming
	on arert_incoming.consultation_id = c.consultation_id
left join crt.person p
	on p.person_id = c.person_id
left join crt.person pp
	on pp.person_id = c.partner_person_id
where c.consultation_number = @consultationNumber




print '         Consultation state           : ' + @consultationState
print '         Dossier context              : ' + convert(varchar(10), @dossierContextId) + '. ' + @dossierContextName
print '         Consultation Person State    : ' + @consultationPersonState
print ''
print case when @consultationCanBeTested = 1 then '  ' else '!!' end + '       Can test run?                : ' + case when @consultationCanBeTested = 1 then 'Yes' else 'No' end
if @ConsultationCanBeTested = 0 
begin
print '!!                                   Tests can not be run for this consultation because it is not yet complete.'
print '!!                                   Please link a person to the consultation and rerun the script to process the consultation.'
end
else
begin -- BEGIN OF TESTS


print ''
print '      ------------------------------------------------------------------------------------------'
print ''
print '       1.   Determine the legal act types that should be included into the results'
print ''
print '            Dossier context           : ' + convert(varchar(10), @dossierContextId) + '. ' + @dossierContextName
print '            Consultation Person State : ' + @consultationPersonState
print ''
print '       1.1. Legal Act Types for the given dossier context and person state:'
print ''
select rt.*
into #legalActTypes
from crt.dossier_context_rule dcr
inner join crt.registration_type rt
	on rt.registration_type_id = dcr.registration_type_id
where dossier_context_id = @dossierContextId
and ((@consultationPersonState = 'DECEASED' and allow_for_deceased = 1) or (@consultationPersonState = 'ALIVE' and allow_for_living = 1))


DECLARE c CURSOR FOR 
SELECT r.register_name, lat.code, lat.name_nl 
FROM #legalActTypes lat
inner join crt.register_type r
	on r.register_type_id = lat.register_type_id
order by r.register_type_id, lat.code

declare @lat_code varchar(5)
declare @lat_name varchar(200)

OPEN c  
FETCH NEXT FROM c INTO @register_name, @lat_code, @lat_name  

WHILE @@FETCH_STATUS = 0  
BEGIN  
      print '              ' + @register_name + '.' + @lat_code + ' - ' + @lat_name
	  FETCH NEXT FROM c INTO @register_name, @lat_code, @lat_name 
END 

CLOSE c  
DEALLOCATE c 

print ''
print '       1.2. Legal Act Types after applying selected consultation registers (from criteria)'
print ''

delete from #legalActTypes where register_type_id not in (select register_type_id from #consultedRegisters)

DECLARE c CURSOR FOR 
SELECT r.register_name, lat.code, lat.name_nl 
FROM #legalActTypes lat
inner join crt.register_type r
	on r.register_type_id = lat.register_type_id
order by r.register_type_id, lat.code

OPEN c  
FETCH NEXT FROM c INTO @register_name, @lat_code, @lat_name  

WHILE @@FETCH_STATUS = 0  
BEGIN  
      print '              ' + @register_name + '.' + @lat_code + ' - ' + @lat_name
	  FETCH NEXT FROM c INTO @register_name, @lat_code, @lat_name 
END 

CLOSE c  
DEALLOCATE c 

print ''
print '      ------------------------------------------------------------------------------------------'
print ''
print '       2.   Determine person nrns to search for'
print ''
print '       2.1. NRN Person                : ' + @personNRN

DECLARE c CURSOR FOR 
SELECT nrn
FROM #previousPersonNrns

declare @nrn varchar(11)
set @tempLoop = 0

OPEN c  
FETCH NEXT FROM c INTO @nrn

WHILE @@FETCH_STATUS = 0  
BEGIN  
	
      print '            ' + case when @tempLoop = 0 then ' + Previous NRNs          : ' else '                            ' end + @nrn 
	  set @tempLoop = @tempLoop + 1
	  FETCH NEXT FROM c INTO @nrn
END 

CLOSE c  
DEALLOCATE c 

print ''
print '       2.2. NRN Partner               : ' + convert(varchar(11), @partnerNRN)

DECLARE c CURSOR FOR 
SELECT nrn
FROM #previousPartnerNrns

set @tempLoop = 0

OPEN c  
FETCH NEXT FROM c INTO @nrn

WHILE @@FETCH_STATUS = 0  
BEGIN  
	
      print '            ' + case when @tempLoop = 0 then ' + Previous NRNs          : ' else '                            ' end + @nrn 
	  set @tempLoop = @tempLoop + 1
	  FETCH NEXT FROM c INTO @nrn
END 

CLOSE c  
DEALLOCATE c 

print ''
print '      ------------------------------------------------------------------------------------------'
print ''
print '       3.   Retrieve legal acts to be part of the results'




print ''
print '       3.1. Retrieve active legal acts for the given types and the person NRN(s)'
print ''


select jd.*
into #results
from crt.juridical_deed jd
inner join #legalActTypes lat
	on lat.registration_type_id = jd.registration_type_id
inner join crt.paper_deed pd (nolock)
	on pd.status_id = 0
	and jd.status_id = 0
	and pd.paper_deed_id = jd.paper_deed_id
where juridical_deed_id in (
	select juridical_deed_id
	from crt.person  (nolock)
	where juridical_deed_id is not null
	and (nrn = @personNRN or nrn in (select nrn from #previousPersonNrns))
)


DECLARE c CURSOR FOR 
SELECT r.juridical_deed_number, rt.register_name, lat.code, lat.name_nl
FROM #results r
inner join crt.registration_type lat
	on lat.registration_type_id = r.registration_type_id
inner join crt.register_type rt
	on rt.register_type_id = lat.register_type_id

declare @jdNumber varchar(50)

OPEN c  
FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name

set @tempLoop = 1

WHILE @@FETCH_STATUS = 0  
BEGIN  
	
      print '               ' + convert(varchar(2), @tempLoop) + '. ' + @jdNumber + '     [' + @register_name + '.' + @lat_code + ' - ' + @lat_name + ']'
	  set @tempLoop +=1
	  FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name
END 

CLOSE c  
DEALLOCATE c 


print ''
print '       3.2. Applying additional filter for CRH with wrong partner'
print ''


		

delete from #results
where juridical_deed_id not in (
	-- sub selects selcts everything that we need to keep
	select r.juridical_deed_id
	from #results r
	inner join crt.registration_type rt
		on r.registration_type_id = rt.registration_type_id
	inner join crt.register_type reg
		on reg.register_type_id = rt.register_type_id
	where (
		@partnerNRN is null -- there is no filtering on partner, so let's keep them all
		or reg.register_name <> 'CRH' -- everything not CRH is not to be removed
		or (
			select count(*) 
			from crt.person 
			where juridical_deed_id = r.juridical_deed_id 
			and nrn != @personNRN 
			and nrn not in (select nrn from #previousPersonNrns) 
			and (
				nrn = @partnerNrn 
				or nrn in (select nrn from #previousPartnerNrns) 
			)) > 0
	)
)

DECLARE c CURSOR FOR 
SELECT r.juridical_deed_number, rt.register_name, lat.code, lat.name_nl
FROM #results r
inner join crt.registration_type lat
	on lat.registration_type_id = r.registration_type_id
inner join crt.register_type rt
	on rt.register_type_id = lat.register_type_id

OPEN c  
FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name

set @tempLoop = 1

WHILE @@FETCH_STATUS = 0  
BEGIN  
	
      print '               ' + convert(varchar(2), @tempLoop) + '. ' + @jdNumber + '     [' + @register_name + '.' + @lat_code + ' - ' + @lat_name + ']'
	  set @tempLoop +=1
	  FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name
END 

CLOSE c  
DEALLOCATE c 


print ''
print '      ------------------------------------------------------------------------------------------'
print ''
print '       4.   Apply GDPR shielding'
print ''

select r.juridical_deed_number, p.nrn
into #results_gdpr
from #results r
inner join #legalActTypes lat
	on r.registration_type_id = lat.registration_type_id
	and lat.definition = 'succession-agreement'
left join crt.person pr1 (nolock)
	on pr1.juridical_deed_id = r.juridical_deed_id
	and pr1.person_role_id = 1
inner join crt.person p (nolock)
	on p.juridical_deed_id = r.juridical_deed_id
	and p.nrn != @personNRN and p.nrn not in (select nrn from #previousPersonNrns)
where @consultationPersonState = 'ALIVE'
or (
	@consultationPersonState = 'DECEASED'
	and pr1.nrn != @personNRN 
	and pr1.nrn not in (select nrn from #previousPersonNrns) -- match for involved party
	)


DECLARE c CURSOR FOR 
SELECT r.juridical_deed_number, rt.register_name, lat.code, lat.name_nl
FROM #results r
inner join crt.registration_type lat
	on lat.registration_type_id = r.registration_type_id
inner join crt.register_type rt
	on rt.register_type_id = lat.register_type_id

OPEN c  
FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name

set @tempLoop = 1

declare @tempLoop2 int = 0

WHILE @@FETCH_STATUS = 0  
BEGIN  
	
      print '               ' + convert(varchar(2), @tempLoop) + '. ' + @jdNumber + '     [' + @register_name + '.' + @lat_code + ' - ' + @lat_name + ']'
	  
	  set @tempLoop +=1


	  DECLARE c2 CURSOR FOR 
	  SELECT nrn
	  FROM #results_gdpr
	  where juridical_deed_number = @jdNumber

	  set @tempLoop2 = 0

	  OPEN c2
	  FETCH next from c2 into @nrn
	  WHILE @@FETCH_STATUS = 0
	  BEGIN
	    if @tempLoop2 = 0 begin print '' end
		print '                 ' + case when @tempLoop2 = 0 then ' Persons to anonymise   : ' else '                          ' end + @nrn 

		SET @tempLoop2 += 1
		FETCH next from c2 into @nrn
	  END

	  CLOSE c2
	  DEALLOCATE c2

	  print ''

	  FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name
END 

CLOSE c  
DEALLOCATE c 


print ''
print '      ------------------------------------------------------------------------------------------'
print ''
print '       5.   Comparing consultation results with expected results'
print ''
print '       5.1. Check that all expected results are also persisted in consultation_results'
print ''

DECLARE c CURSOR FOR 
SELECT r.juridical_deed_number, rt.register_name, lat.code, lat.name_nl
FROM #results r
inner join crt.registration_type lat
	on lat.registration_type_id = r.registration_type_id
inner join crt.register_type rt
	on rt.register_type_id = lat.register_type_id

OPEN c  
FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name

set @tempLoop = 1

declare @isPersisted int



WHILE @@FETCH_STATUS = 0  
BEGIN  
	
      print '               ' + convert(varchar(2), @tempLoop) + '. ' + @jdNumber + '     [' + @register_name + '.' + @lat_code + ' - ' + @lat_name + ']'
	  
	  select @isPersisted = case when consultation_results_id is null then 0 else 1 end
	  from #results r
	  inner join crt.consultation c (nolock)
		on c.consultation_number = @consultationNumber
		and r.juridical_deed_number = @jdNumber
	  left join crt.consultation_results cr (nolock)
		on cr.consultation_id = c.consultation_id
		and cr.juridical_deed_id = r.juridical_deed_id
	 
	  
	  print case when @isPersisted = 1 then '  OK' else '!!!!' end +  '              Expected legal act ' + @jdNumber + case when @isPersisted = 1 then ' is found in the persisted results' else ' is NOT found in the persisted results' end
	  if @isPersisted = 0 begin set @errorCount += 1 end
	 

	  print ''
	  set @tempLoop += 1

	  FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name
END 

CLOSE c  
DEALLOCATE c 

print ''
print '       5.2. Check that all there are no unexpected persisted results'
print ''


DECLARE c CURSOR FOR 
SELECT jd.juridical_deed_number, reg.register_name, rt.code, rt.name_nl
from crt.consultation c
inner join crt.consultation_results cr
	on cr.consultation_id = c.consultation_id
inner join crt.juridical_deed jd
	on jd.juridical_deed_id = cr.juridical_deed_id
inner join crt.registration_type rt
	on rt.registration_type_id = jd.registration_type_id
inner join crt.register_type reg
	on reg.register_type_id = rt.register_type_id
where c.consultation_number = @consultationNumber


OPEN c  
FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name

set @tempLoop = 1

declare @isExpected int = 0

WHILE @@FETCH_STATUS = 0  
BEGIN  
	
      print '               ' + convert(varchar(2), @tempLoop) + '. ' + @jdNumber + '     [' + @register_name + '.' + @lat_code + ' - ' + @lat_name + ']'
	  
	  select @isExpected = case when r.juridical_deed_id is null then 0 else 1 end
	  from crt.juridical_deed jd
	  left join #results r
		on r.juridical_deed_id = jd.juridical_deed_id
	  where jd.juridical_deed_number = @jdNumber
	  
	  
	  print case when @isExpected = 1 then '  OK' else '!!!!' end +  '              Persisted legal act result ' + @jdNumber + case when @isExpected = 1 then ' is expected' else ' is NOT expected' end
	  if @isExpected = 0 begin set @errorCount += 1 end
	 

	  print ''
	  set @tempLoop += 1

	  FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name
END 

CLOSE c  
DEALLOCATE c 

print ''
print '       5.3. Check GDPR information for all persisted and expected results'
print ''



declare @gdprJson nvarchar(max)

DECLARE c CURSOR FOR 
SELECT jd.juridical_deed_number, reg.register_name, rt.code, rt.name_nl, json_query(cr.gdpr_info, '$')
from crt.consultation c
inner join crt.consultation_results cr
	on cr.consultation_id = c.consultation_id
inner join crt.juridical_deed jd
	on jd.juridical_deed_id = cr.juridical_deed_id
inner join crt.registration_type rt
	on rt.registration_type_id = jd.registration_type_id
inner join crt.register_type reg
	on reg.register_type_id = rt.register_type_id
inner join #results r
	on r.juridical_deed_id = jd.juridical_deed_id
where c.consultation_number = @consultationNumber

OPEN c  
FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name, @gdprJson

set @tempLoop = 1

WHILE @@FETCH_STATUS = 0  
BEGIN  
	
      print '               ' + convert(varchar(2), @tempLoop) + '. ' + @jdNumber + '     [' + @register_name + '.' + @lat_code + ' - ' + @lat_name + ']'

	  declare @found int

	  declare c2 cursor for
	  SELECT g.nrn
	  from #results_gdpr g
	  where g.juridical_deed_number = @jdNumber

	  open c2
	  FETCH NEXT FROM c2 INTO @nrn

	  WHILE @@FETCH_STATUS = 0
	  BEGIN

		select @found = count(*)
		from (
			  select nrn
			  from openjson(@gdprJson) with (
				nrns nvarchar(max) '$.nrns' AS JSON
			  ) as i
			  cross apply openjson(i.nrns) with (
				nrn nvarchar(max) '$'
			  )
		) f
		where f.nrn = @nrn

		print case when @found = 1 then '  OK' else '!!!!' end +  '              Expected NRN ' + @nrn + case when @found = 1 then ' was also found in persisted results' else ' was NOT found in persisted results' end
		if @found = 0 begin set @errorCount += 1 end

		FETCH NEXT FROM c2 INTO @nrn
	  END 

	  close c2
	  deallocate c2

	  declare c2 cursor for
	  select nrn
	  from openjson(@gdprJson) with (
		nrns nvarchar(max) '$.nrns' AS JSON
	  ) as i
	  cross apply openjson(i.nrns) with (
		nrn nvarchar(max) '$'
	  )

	  open c2
	  FETCH NEXT FROM c2 INTO @nrn

	  WHILE @@FETCH_STATUS = 0
	  BEGIN

		select @found = count(*)
		from #results_gdpr g
		where g.nrn = @nrn
		and g.juridical_deed_number = @jdNumber

		print case when @found = 1 then '  OK' else '!!!!' end +  '              Persisted NRN ' + @nrn + case when @found = 1 then ' was expected' else ' was NOT expected' end
		if @found = 0 begin set @errorCount += 1 end

		FETCH NEXT FROM c2 INTO @nrn
	  END 

	  close c2
	  deallocate c2
	  print ''

	  set @tempLoop += 1

	  FETCH NEXT FROM c INTO @jdNumber, @register_name, @lat_code, @lat_name, @gdprJson
END 

CLOSE c  
DEALLOCATE c 

print ''
if @errorCount = 0
begin
print '      ******************************************************************************************'
print '      *                                                                                        *'
print '      *  CONGRATULATIONS!  TEST WAS SUCCESSFULLY COMPLETED                                     *'
print '      *                                                                                        *'
print '      ******************************************************************************************'
end
else
begin
print '      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
print '      !                                                                                        !'
print '      !  TEST FAILED                                                                           !'
print '      !                                                                                        !'
print '      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
print '         Errors: ' + convert(varchar(3), @errorCount)
end



drop table #legalActTypes
drop table #results
drop table #results_gdpr

end -- END OF TESTS

drop table #consultedRegisters
drop table #previousPersonNrns
drop table #previousPartnerNrns


