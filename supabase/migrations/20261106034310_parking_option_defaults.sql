-- Upgrade known defaults without changing custom apartment settings or history.
alter table public.apartments
  alter column allowed_floors set default array['F1','F2','F3','F4','F5','B1','B2','B3','B4','B5'],
  alter column allowed_zones set default array['A','B','C','D','E','F','가','나','다','라','마','바'];

update public.apartments
set allowed_floors = array['F1','F2','F3','F4','F5','B1','B2','B3','B4','B5']
where allowed_floors = array['F5','F4','F3','F2','F1','B1','B2','B3','B4','B5','B6']
   or allowed_floors = array['B1','B2','B3','B4'];

update public.apartments
set allowed_zones = array['A','B','C','D','E','F','가','나','다','라','마','바']
where allowed_zones = array['A','B','C','D','E'];
