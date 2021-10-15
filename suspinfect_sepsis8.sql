
--este es sospecha de infección que usa lo ajustado en abx_micro_poe_sepsis8.
--al parecer genera mas pacientes infectados
DROP TABLE IF EXISTS suspinfect_poe_sepsis8 CASCADE;
CREATE TABLE suspinfect_poe_sepsis8 as
with abx as
(
  select icustay_id
    , suspected_infection_time
    , specimen, positiveculture
    , antibiotic_name
    , antibiotic_time
	, si_starttime
	, si_endtime
    , ROW_NUMBER() OVER
    (
      PARTITION BY icustay_id
      ORDER BY suspected_infection_time
    ) as rn
  from abx_micro_poe_sepsis8
)
select
  subject_id
  ,ie.icustay_id
  , antibiotic_name
  , antibiotic_time
  , suspected_infection_time
  , specimen, positiveculture
  , si_starttime
  , si_endtime
from icustays ie
left join abx
  on ie.icustay_id = abx.icustay_id
  and abx.rn = 1
order by ie.icustay_id;