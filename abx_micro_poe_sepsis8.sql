-- defines suspicion of infection using prescriptions + microbiologyevents
--se utilizará esta consulta para ampliar la busqueda de pacientes con sospecha de infección
DROP TABLE IF EXISTS abx_micro_poe_sepsis8 CASCADE;
CREATE TABLE abx_micro_poe_sepsis8 as
with abx as
(
  select pr.hadm_id
  , pr.drug as antibiotic_name
  , pr.startdate as antibiotic_time
  , pr.enddate as antibiotic_endtime
  from prescriptions pr
  -- inner join to subselect to only antibiotic prescriptions
  inner join abx_poe_list ab
      on pr.drug = ab.drug
)
-- get cultures for each icustay
-- note this duplicates prescriptions
-- each ICU stay in the same hospitalization will get a copy of all prescriptions for that hospitalization
, ab_tbl as
(
  select
        ie.subject_id, ie.hadm_id, ie.icustay_id
      , ie.intime, ie.outtime
      , abx.antibiotic_name
      , abx.antibiotic_time
      , abx.antibiotic_endtime
  from icustays ie
  left join abx
      on ie.hadm_id = abx.hadm_id
)
, me as --Microbiology event
(
  select hadm_id
    , chartdate, charttime
    , spec_type_desc
    , max(case when org_name is not null and org_name != '' then 1 else 0 end) as PositiveCulture
  from microbiologyevents
  group by hadm_id, chartdate, charttime, spec_type_desc
)
, ab_fnl as
(
  select 
      ab_tbl.icustay_id, ab_tbl.intime, ab_tbl.outtime
    , ab_tbl.antibiotic_name
    , ab_tbl.antibiotic_time
    , coalesce(me72.charttime,me72.chartdate) as last72_charttime
    , coalesce(me24.charttime,me24.chartdate) as next24_charttime

    , me72.positiveculture as last72_positiveculture
    , me72.spec_type_desc as last72_specimen
    , me24.positiveculture as next24_positiveculture
    , me24.spec_type_desc as next24_specimen
  from ab_tbl
  -- blood culture in last 72 hours
	--96 se puso por 72
  left join me me72
    on ab_tbl.hadm_id = me72.hadm_id--cambiado
    and ab_tbl.antibiotic_time is not null
    and
    (
      -- if charttime is available, use it
      (
          ab_tbl.antibiotic_time > me72.charttime
      and ab_tbl.antibiotic_time <= me72.charttime + interval '72' hour
      )
      OR
      (
      -- if charttime is not available, use chartdate
          me72.charttime is null
      and ab_tbl.antibiotic_time > me72.chartdate
      and ab_tbl.antibiotic_time < me72.chartdate + interval '96' hour -- could equally do this with a date_trunc, but that's less portable
      )
    )
  -- blood culture in subsequent 24 hours
  left join me me24
    on ab_tbl.hadm_id = me24.hadm_id
    and ab_tbl.antibiotic_time is not null
    and me24.charttime is not null
    and
    (
      -- if charttime is available, use it
      (
          ab_tbl.antibiotic_time > me24.charttime - interval '24' hour
      and ab_tbl.antibiotic_time <= me24.charttime
      )
      OR
      (
      -- if charttime is not available, use chartdate
          me24.charttime is null
      and ab_tbl.antibiotic_time > me24.chartdate
      and ab_tbl.antibiotic_time <= me24.chartdate + interval '24' hour
      )
    )
)
, ab_laststg as
(
select
  icustay_id
  , antibiotic_name
  , antibiotic_time
  , last72_charttime --cambiado
  , next24_charttime
  , last72_positiveculture--modificado se incluye
  , next24_positiveculture --modIFICADO SE INCLUYE
  -- time of suspected infection: either the culture time (if before antibiotic), or the antibiotic time
  , case
      when coalesce(last72_charttime,antibiotic_time) is null --cambiado last72 
        then 0
      else 1 end as suspected_infection

  , coalesce(last72_charttime,antibiotic_time) as suspected_infection_time --cambiado 

  -- the specimen that was cultured
  , case
      when last72_charttime is not null--cambiado
        then last72_specimen--cambiado
      when next24_charttime is not null
        then next24_specimen
    else null
  end as specimen

  -- whether the cultured specimen ended up being positive or not POSITIVE CULTURE
  , case
     when last72_charttime  is not null
        then last72_positiveculture 
	when next24_charttime  is not null--cambiado
        then next24_positiveculture --cambiado
    else null
  end as positiveculture
from ab_fnl
)
select
  icustay_id
  , antibiotic_name
  , antibiotic_time
  , last72_charttime
  --cambiado
  , next24_charttime--se incluye
  , suspected_infection_time
  -- -- the below two fields are used to extract data - modifying them facilitates sensitivity analyses
   , suspected_infection_time - interval '48' hour as si_starttime-- esta es la ventana de tiempo de inicio y fin de sospecha de infección
   , suspected_infection_time + interval '24' hour as si_endtime
  , specimen
  , positiveculture
  , last72_positiveculture 
  , next24_positiveculture
from ab_laststg
order by icustay_id, antibiotic_time;