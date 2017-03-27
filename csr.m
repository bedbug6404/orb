classdef csr
  methods(Static)
    function log(msg)
      logname=fullfile(fileparts(mfilename),'import_calpar.log');
      if ~exist('msg','var')
        if ~isempty(dir(logname)); delete(logname); end
      else
        fid = fopen(logname,'a');  
        fprintf(fid,[strjoin(msg,'\n'),'\n']);
        fclose(fid);
      end
    end
    function report(debug,idx,context,id,labels,data)
      if isempty(idx); return; end
      [~,ids]=fileparts(id);
      if isempty(ids); ids=id; end
      msg=cell(1,numel(idx)+2);
      msg{1}=str.tablify([34,30,1,5],[context,' for'],ids,':',num2str(numel(idx)));
      msg{2}=str.tablify(20,'data','idx',labels{:});
      for k=1:numel(idx)
        msg_data=cell(1,numel(data));
        for l=1:numel(data)
          msg_data{l}=data{l}(idx(k));
        end
        msg{k+2}=str.tablify(20,ids,idx(k),msg_data{:});
      end
      if debug;disp(strjoin(msg(1:min([12,numel(msg)])),'\n')); else disp(msg{1}); end; csr.log(msg)
    end
    function obj=import_calpar(obj,dataname,varargin)
      %open log file
      csr.log
      % parse mandatory arguments
      p=inputParser;
      p.addRequired('dataname', @(i) isa(i,'datanames'));
      p.parse(dataname);
      %retrieve product info
      product=obj.mdget(dataname);
      %check if data is already in matlab format
      if ~product.isfile('data')
        %get names of parameters and levels
        levels     =product.mdget('levels');
        fields     =product.mdget('fields');
        fields_out =product.mdget('fields_out');
        sats       =product.mdget('sats');
        bias_files =product.mdget('bias_files');
        param_col  =product.mdget('param_col');
        jobid_col  =product.mdget('jobid_col');
        arclen_col =product.mdget('arclen_col');
        t0_col     =product.mdget('t0_col');
        %need to get long-term biases
        for s=1:numel(sats)
          ltb.(sats{s})=flipud(transpose(dlmread(bias_files{s})));
        end
        %load data
        for i=1:numel(levels)
          for j=1:numel(fields)
            tmp=struct('A',[],'B',[]);
            %read data
            for s=1:numel(sats)
              f=fullfile(product.mdget('import_dir'),['gr',sats{s},'.',fields{j},'.',levels{i},'.GraceAccCal']);
              tmp.(sats{s})=simpletimeseries.import(f,'cut24hrs',false);
              %enforce the long-term biases
              switch fields{j}
              case 'AC0X'
                lbt_idx=2;
              case {'AC0Y1','AC0Y2','AC0Y3','AC0Y4','AC0Y5','AC0Y6','AC0Y7','AC0Y8'}
                lbt_idx=3;
              case 'AC0Z'
                lbt_idx=4;
              otherwise
                lbt_idx=0;
              end
              if lbt_idx>0
                switch levels{i}
                case {'aak','accatt'}
                  %need to ensure timestamps are in agreement with t0
                  assert(tmp.(sats{s}).width < t0_col || all(tmp.(sats{s}).mjd==tmp.(sats{s}).y(:,t0_col)),[mfilename,':',...
                    'discrepancy between time domain and t0.'])
                end
                t=tmp.(sats{s}).mjd-ltb.(sats{s})(2,1);
                tmp.(sats{s})=tmp.(sats{s}).assign(...
                  [tmp.(sats{s}).y(:,param_col)+polyval(...
                    ltb.(sats{s})(:,lbt_idx),t),...
                    tmp.(sats{s}).y(:,[1:param_col-1,param_col+1:end])...
                  ]...
                );
              end

              %additional processing: add end of arcs
              switch levels{i}
              case {'aak','accatt'}
                %get arc stars
                arc_starts=tmp.(sats{s}).t;
                %build arc ends
                arc_ends=[arc_starts(2:end);dateshift(arc_starts(end),'end','day')]-seconds(1);
                %arc ends are at maximum 24 hours after arc starts (only for those arcs starting at mid-night)
                fix_idx=arc_ends-arc_starts>days(1) & ...
                  seconds(arc_starts-dateshift(arc_starts,'start','day'))<tmp.(sats{s}).t_tol;
                arc_ends(fix_idx)=arc_starts(fix_idx)+days(1)-seconds(1);
              case 'estim'
                %get arc stars
                arc_starts=tmp.(sats{s}).t;
                %build arc ends (arc duration given explicitly)
                arc_ends=arc_starts+seconds(tmp.(sats{s}).y(:,arclen_col))-seconds(1);
                %patch missing arc durations
                idx=find(isnat(arc_ends));
                %report edge cases
                csr.report(obj.debug,idx,'Arcs without arc length',f,...
                  {'arc start','arc duraction'},...
                  {arc_starts,tmp.(sats{s}).y(:,arclen_col)}...
                )
                %fix it
                if ~isempty(idx);
                  arc_ends(idx)=dateshift(arc_starts(idx),'end','day')-seconds(1);
                end
                
                %get seconds-of-day of arc ends
                sod_arc_ends=seconds(arc_ends-dateshift(arc_ends,'start','day'));
                %find the 24hrs arcs (those that have ~0 seconds of days)
                idx=find(sod_arc_ends<tmp.(sats{s}).t_tol);
                %push those arcs to midnight and remove 1 second
                arc_ends(idx)=dateshift(arc_ends(idx),'start','day')-seconds(1);
                %check for ilegal arc durations
                idx=find(sod_arc_ends>86400);
                csr.report(obj.debug,idx,'Arcs ending after midnight',f,...
                  {'arc start','arc end','sod arc end'},...
                  {arc_starts,arc_ends,sod_arc_ends}...
                )
                %fix it
                if ~isempty(idx)
                  arc_ends(idx)=dateshift(arc_ends(idx),'start','day')-seconds(1);
                end
              end
              
              %bug trap
              assert(all(~isnat(arc_ends)) && all(~isnat(arc_ends)),...
                [mfilename,': found NaT in the arc starts/ends'])
              %surpress over-lapping arcs
              idx=find(arc_starts(2:end)-arc_ends(1:end-1)<0);
              csr.report(obj.debug,idx,'Over-lapping arcs',f,...
                {'curr arc start','curr arc end','next arc start'},...
                {arc_starts,arc_ends,[arc_starts(2:end);arc_starts(1)]}...
              )
              %fix it
              if ~isempty(idx)
                arc_ends(idx)=arc_starts(idx+1)-seconds(1);
              end
              
              %compute arc lengths
              arc_length=arc_ends-arc_starts;

              %fancy stuff: handle parameters defined as arc segments
              if ~isempty(strfind(fields{j},'AC0Y'))
                %there are 8 segments per arc
                periodicity=arc_length/8;
                %get day location for this parameter
                day_loc=str2double(fields{j}(end));
                %get sub-arc starts/ends
                sub_arc_starts=arc_starts+periodicity*(day_loc-1);
                  sub_arc_ends=arc_starts+periodicity*(day_loc  )-seconds(1);
                %cap sub-arc start/ends to be within the current arc
                idx={...
                  find(sub_arc_starts>arc_ends  ),...
                  find(sub_arc_starts<arc_starts),...
                  find(sub_arc_ends  >arc_ends  ),...
                  find(sub_arc_ends  <arc_starts)...
                };
                msg={...
                  'Sub-arc starts after arc ends',...
                  'Sub-arc starts before arc starts',...
                  'Sub-arc ends after arc ends',...
                  'Sub-arc ends before arc starts'...
                };
                for k=1:numel(idx)
                  csr.report(obj.debug,idx{k},msg{k},f,...
                    {'sub-arc start','sub-arc end',...
                        'arc start',     'arc end',...
                        'periodicity'},...
                    {sub_arc_starts(idx{k}),sub_arc_ends(idx{k}),...
                         arc_starts(idx{k}),    arc_ends(idx{k}),...
                        periodicity(idx{k})}...
                  )
                  %fix it
                  if ~isempty(idx{k})
                    switch k
                    case 1; sub_arc_starts(idx{k})=arc_ends(  idx{k});
                    case 2; sub_arc_starts(idx{k})=arc_starts(idx{k});
                    case 3; sub_arc_ends(  idx{k})=arc_ends(  idx{k});
                    case 4; sub_arc_ends(  idx{k})=arc_starts(idx{k});
                    end
                  end
                end
                %propagate the arc extremeties
                arc_starts=sub_arc_starts;
                  arc_ends=sub_arc_ends;
              end

              %propagate data
              arc_start_y=tmp.(sats{s}).y;
                arc_end_y=tmp.(sats{s}).y;

              % set the arc length to zero for arc ends
              switch levels{i}
              case 'estim'
                arc_end_y(:,arclen_col)=0;
              end
                       
             %build timeseries with arc starts
              arc_start_ts=simpletimeseries(arc_starts,arc_start_y,...
                'format','datetime',...
                'labels',tmp.(sats{s}).labels,...
                'units',tmp.(sats{s}).y_units,...
                'timesystem',tmp.(sats{s}).timesystem,...
                'descriptor',tmp.(sats{s}).descriptor...
              );
              %build timeseries with arc ends
              arc_end_ts=simpletimeseries(arc_ends,arc_end_y,...
                'format','datetime',...
                'labels',tmp.(sats{s}).labels,...
                'units',tmp.(sats{s}).y_units,...
                'timesystem',tmp.(sats{s}).timesystem,...
                'descriptor',['end of arcs for ',tmp.(sats{s}).descriptor]...
              );
              
              %additional processing: add gaps
              gap_idx=[...
                abs(seconds(arc_ends(1:end-1)+seconds(1)-arc_starts(2:end))) > tmp.(sats{s}).t_tol;...
              false];
              gap_t=arc_ends(gap_idx)+seconds(1);
              %build timeseries with arc ends
              gap_ts=simpletimeseries(gap_t,nan(numel(gap_t),tmp.(sats{s}).width),...
                'format','datetime',...
                'labels',tmp.(sats{s}).labels,...
                'units',tmp.(sats{s}).y_units,...
                'timesystem',tmp.(sats{s}).timesystem,...
                'descriptor',['gaps for ',tmp.(sats{s}).descriptor]...
              );
            
              if obj.debug
%                 t0=datetime('16-Aug-2002');t1=datetime('21-Aug-2002');
%                 t0=datetime('04-Apr-2002');t1=datetime('08-Apr-2002');
%                 t0=datetime('12-Jan-2003');t1=datetime('16-Jan-2003');
%                 t0=datetime('2003-11-29');t1=datetime('2003-12-02');
                t0=datetime('2012-06-29');t1=datetime('2012-07-03');
                o=tmp.(sats{s}).trim(t0,t1);
                disp(str.tablify(22,'orignal t','original y'))
                for di=1:o.length
                  disp(str.tablify(22,o.t(di),o.y(di,param_col)))
                end
                 as=arc_start_ts.trim(t0,t1);
                 ae=  arc_end_ts.trim(t0,t1);
                 disp(str.tablify(22,'arc start t','arc start y','arc end t','arc end y'))
                 for di=1:min([as.length,ae.length])
                   disp(str.tablify(22,as.t(di),as.y(di,param_col),ae.t(di),ae.y(di,param_col)))
                 end
                 g=gap_ts.trim(t0,t1);
                 if ~isempty(g)
                   disp(str.tablify(22,'gap t','gap y'))
                   for di=1:g.length
                     disp(str.tablify(22,g.t(di),g.y(di,param_col)))
                   end
                 end
              end

              %augment the original timeseries with the end-of-arcs and gaps (only new data)
              tmp.(sats{s})=arc_start_ts.augment(arc_end_ts,'only_new_data',true).augment(gap_ts,'only_new_data',true);
              
              if obj.debug
                au=tmp.(sats{s}).trim(t0,t1);
                disp(str.tablify(22,'augmented t','augmented y'))
                for di=1:au.length
                  disp(str.tablify(22,au.t(di),au.y(di,param_col)))
                end
                keyboard
              end

            end
            
%             %ensure date is compatible between the satellites
%             if ~tmp.A.isteq(tmp.B)
%               [tmp.A,tmp.B]=tmp.A.merge(tmp.B);
%             end
            %propagate data to object
            for s=1:numel(sats)
              obj=obj.sat_set(product.dataname.type,levels{i},fields{j},sats{s},tmp.(sats{s}));
            end
            disp(str.tablify([15,6,3,6],'loaded data for',levels{i},'and',fields{j}))
          end
        end
               
        %merge cross-track accelerations together
        ac0y='AC0Y';
        field_part_list={'','D','Q'};
        %loop over all levels and sats
        for i=1:numel(levels)
          for s=1:numel(sats)
            for f=1:numel(field_part_list)
              %start with first field
              field1=[ac0y,field_part_list{f},'1'];
              ts_now=obj.sat_get(product.dataname.type,levels{i},field1,sats{s});
              %loop over all other fields
              for fpl=2:8
                field=[ac0y,field_part_list{f},num2str(fpl)];
                ts_now=ts_now.augment(obj.sat_get(product.dataname.type,levels{i},field,sats{s}),'quiet',true);
              end
              %save the data
              obj=obj.sat_set(product.dataname.type,levels{i},[ac0y,field_part_list{f}],sats{s},ts_now);
              disp(str.tablify([29,5,3,6,3,7],'merged cross-track parameter',[ac0y,field_part_list{f}],...
                'for',levels{i},'and',['GRACE-',sats{s}]))
            end
          end
        end

        %loop over all sat and level to check Job IDs agreement across all output fields
        for i=1:numel(levels)
          for s=1:numel(sats)
            %gather names for this sat and level
            names=obj.vector_names(product.dataname.type,levels{i},fields_out,sats{s});
            for j=1:numel(names)-1
              d1=obj.data_get(names{j  });
              d2=obj.data_get(names{j+1});
              [~,i1,i2]=intersect(d1.t,d2.t);
              bad_idx=find(...
                d1.y(i1,jobid_col) ~= d2.y(i2,jobid_col) & ...
                d1.mask(i1) & ...
                d2.mask(i2) ...
              );
              if ~isempty(bad_idx)
                n=numel(bad_idx);
                msg=cell(1,2*n+2);
                msg{1}=str.tablify([5,6,24],'found',numel(bad_idx),'Job ID inconsistencies:');
                msg{2}=str.tablify([26,6,20,10],'data name','idx','t','Job ID');
                for k=1:n
                  idx=i1(bad_idx(k));
                  msg{2*k+1}=str.tablify([26,6,20,10],names{j  }.name,idx,d1.t(idx),d1.y(idx,jobid_col));
                  idx=i2(bad_idx(k));
                  msg{2*k+2}=str.tablify([26,6,20,10],names{j+1}.name,idx,d2.t(idx),d2.y(idx,jobid_col));
                end
                error([mfilename,':',strjoin(msg,'\n')])
              end
            end
          end
        end

        %loop over all sats, levels and fields to:
        % - in case of estim: ensure that there are no arcs with lenghts longer than consecutive time stamps
        % - in case of aak and accatt: ensure that the t0 value is the same as the start of the arc
        for s=1:numel(sats)
          %loop over all required levels
          for i=1:numel(levels)
            switch levels{i}
            case 'estim'
              %this check ensures that there are no arcs with lenghts longer than consecutive time stamps
              for j=1:numel(fields_out)
                %some fields do not have t0
                if ~any(fields_out{j}(end)=='DQ') || ~isempty(strfind(fields_out{j},'Y'))
                  disp(str.tablify([8,10,6,6,1],'Skipping',product.dataname.type,levels{i},fields_out{j},sats{s}))
                  continue
                end
                disp(str.tablify([8,10,6,6,1],'Checking',product.dataname.type,levels{i},fields_out{j},sats{s}))
                %save time series into dedicated var
                ts_now=obj.sat_get(product.dataname.type,levels{i},fields_out{j},sats{s});
                %forget about epochs that have been artificially inserted to represent gaps and end of arcs
                idx1=find(diff(ts_now.t)>seconds(1));
                %get arc lenths
                al=ts_now.y(idx1,arclen_col);
                %get consecutive time difference
                dt=[seconds(diff(ts_now.t(idx1)));0];
                %find arcs that span over time stamps
                bad_idx=find(al-dt>1); %no abs here!
                %report if any such epochs have been found
                csr.report(obj.debug,bad_idx,'Ilegal arc length in the data',[levels{i},'.',fields_out{j},'.',sats{s}],...
                  {'global idx','arc init t','arc length','succ time diff','delta arc len'},...
                  {idx1,ts_now.t(idx1),al,dt,al-dt}...
                ) %#ok<FNDSB>
              end
            case {'aak','accatt'}
              %this check ensures that the t0 value is the same as the start of the arc
              for j=1:numel(fields_out)
                %the Y parameter was constructed from multitple parameters and some fields do not have t0
                if ~any(fields_out{j}(end)=='DQ') || ~isempty(strfind(fields_out{j},'Y')) 
                  disp(str.tablify([8,10,6,6,1],'Skipping',product.dataname.type,levels{i},fields_out{j},sats{s}))
                  continue
                end
                disp(str.tablify([8,10,6,6,1],'Checking',product.dataname.type,levels{i},fields_out{j},sats{s}))
                %save time series into dedicated var
                ts_now=obj.sat_get(product.dataname.type,levels{i},fields_out{j},sats{s});
                %forget about epochs that have been artificially inserted to represent forward steps
                idx1=find(diff(ts_now.t)>seconds(1));
                %get t0
                t0=simpletimeseries.utc2gps(datetime(ts_now.y(idx1,t0_col),'convertfrom','modifiedjuliandate'));
                %find arcs that have (much) t0 different than their first epoch
                bad_idx=find(...
                  abs(ts_now.t(idx1)-t0)>seconds(1) & ...
                  ts_now.mask(idx1) & ...                          %ignore gaps
                  [true;diff(ts_now.y(idx1,jobid_col))~=0] ...     %ignore epochs inside the same arc
                );
                %report if any such epochs have been found
                csr.report(obj.debug,bad_idx,'Ilegal t0 in the data',[levels{i},'.',fields_out{j},'.',sats{s}],...
                  {'global idx','arc init time','t0','delta time'},...
                  {idx1,ts_now.t(idx1),t0,ts_now.t(idx1)-t0}...
                ) %#ok<FNDSB>
              end
            end
          end
        end
        %save data
        s=obj.datatype_get(product.dataname.type); %#ok<*NASGU>
        save(char(product.file('data')),'s');
        clear s
      else
        %load data
        load(char(product.file('data')),'s');
        levels=fieldnames(s); %#ok<NODEF>
        for i=1:numel(levels)
          obj=obj.level_set(product.dataname.type,levels{i},s.(levels{i}));
        end
      end
    end
    function import_calpar_debug_plots(debug)
      if ~exist('debug','var') || isempty(debug)
        debug=false;
      end
      %get current git version
      [status,timetag]=system(['git log -1 --format=%cd --date=iso-local ',mfilename,'.m']);
      %get rid of timezone and leading trash
      timetag=timetag(9:27);
      %sanity
      assert(status==0,[mfilename,': could not determine git time tag'])
      %create dir for plots
      plot_dir=fullfile('plot','import_calpar_debug_plots',timetag);
      if isempty(dir(plot_dir)); mkdir(plot_dir); end

      %load calibration parameters
      a=datastorage('debug',debug).init('grace.calpar_csr','plot_dir',plot_dir);
      %retrieve product info
      sats=a.mdget(datanames('grace.calpar_csr')).mdget('sats');
      %define start/stop pairs and level
      i=0;ssl=struct([]);
      i=i+1; ssl(i).field={'AC0X','AC0Y','AC0Z'};
      ssl(i).start=datetime('2002-08-06 00:00:00');
      ssl(i).stop =datetime('2002-08-06 23:59:59');
      i=i+1; ssl(i).field={'AC0X','AC0Y','AC0Z'};
      ssl(i).start=datetime('2002-08-16 00:00:00');
      ssl(i).stop =datetime('2002-08-18 23:59:59');
      i=i+1; ssl(i).field={'AC0X','AC0Y','AC0Z'};
      ssl(i).start=datetime('2003-01-12 00:00:00');
      ssl(i).stop =datetime('2003-01-15 00:00:00');
      i=i+1; ssl(i).field={'AC0X','AC0Y','AC0Z'};
      ssl(i).start=datetime('2003-11-29 00:00:00');
      ssl(i).stop =datetime('2003-12-02 00:00:00');
      i=i+1; ssl(i).field={'AC0X','AC0Y','AC0Z','AC0XD','AC0YD','AC0ZD','AC0XQ','AC0YQ','AC0ZQ'};
      ssl(i).start=datetime('2006-06-03 00:00:00');
      ssl(i).stop =datetime('2006-06-07 00:00:00');
      i=i+1; ssl(i).field={'AC0X','AC0Y','AC0Z','AC0XD','AC0YD','AC0ZD','AC0XQ','AC0YQ','AC0ZQ'};
      ssl(i).start=datetime('2006-06-12 00:00:00');
      ssl(i).stop =datetime('2006-06-19 00:00:00');
      i=i+1; ssl(i).field={'AC0X','AC0Y','AC0Z'};
      ssl(i).start=datetime('2012-06-30 00:00:00');
      ssl(i).stop =datetime('2012-07-03 00:00:00');
      %loop over the data
      for i=1:numel(ssl)
        p=a.trim(ssl(i).start,ssl(i).stop);
        for f=1:numel(ssl(i).field)
          for s=1:numel(sats)
            dataname_now={'grace','calpar_csr','',ssl(i).field{f},sats{s}};
            p.plot(...
              datanames(dataname_now),...
              'plot_file_full_path',false,...
              'plot_together','level'...
            );
          end
        end
      end
    end
    function obj=compute_calmod(obj,dataname,varargin)
      % parse mandatory arguments
      p=inputParser;
      p.addRequired('dataname', @(i) isa(i,'datanames'));
      p.parse(dataname);
      %retrieve products info
      product=obj.mdget(dataname);
      %paranoid sanity
      if product.nr_sources~=2
        error([mfilename,': number of sources in product ',dataname,...
          ' is expected to be 2, not ',num2str(product.nr_sources),'.'])
      end
      %get sources
      calparp=obj.mdget(product.sources(1));
      l1baccp=obj.mdget(product.sources(2));
      %retrieve relevant parameters
      levels    =calparp.mdget('levels');
      sats      =calparp.mdget('sats');
      param_col =calparp.mdget('param_col');
      coords    =calparp.mdget('coords');
      for s=1:numel(sats)
        %gather quantities
        acc=obj.sat_get(l1baccp.dataname.type,l1baccp.dataname.level,l1baccp.dataname.field,sats{s});
        if ~isa(acc,'simpletimeseries')
          %patch nan calibration model
          calmod=simpletimeseries(...
            [obj.start;obj.stop],...
            nan(2,numel(obj.par.acc.data_col_name))...
          );
        else
          %loop over all 
          for l=1:numel(levels)
            %init models container
            calmod=simpletimeseries(acc.t,zeros(acc.length,numel(coords))).copy_metadata(acc);
            calmod.descriptor=['calibration model ',levels{l},' GRACE-',upper(sats{s})];
            disp(['Computing the ',calmod.descriptor])
            for i=1:numel(coords)
              %build nice structure with the relevant calibration parameters
              cal=struct(...
                'ac0' ,obj.sat_get(calparp.dataname.type,levels{l},['AC0',coords{i}    ],sats{s}).interp(acc.t),...
                'ac0d',obj.sat_get(calparp.dataname.type,levels{l},['AC0',coords{i},'D'],sats{s}).interp(acc.t),...
                'ac0q',obj.sat_get(calparp.dataname.type,levels{l},['AC0',coords{i},'Q'],sats{s}).interp(acc.t)...
              );
              %sanity
              if any([isempty(acc),isempty(cal.ac0),isempty(cal.ac0d),isempty(cal.ac0q)])
                error([mfilename,': not all data is available to perform this operation.'])
              end
              %retrieve time domain (it is the same for all cal pars)
              fields=fieldnames(cal);
              for f=1:numel(fields)
                t.(fields{f})=days(acc.t-simpletimeseries.ToDateTime(cal.(fields{f}).y(:,end),'modifiedjuliandate'));
              end
              %paranoid sanity check
              good_idx=~isnan(t.ac0);
              if any(t.ac0(good_idx)~=t.ac0d(good_idx)) || any(t.ac0(good_idx)~=t.ac0q(good_idx))
                error([mfilename,': calibration time domain inconsistent between parameters, debug needed!'])
              end
              
              
              � preciso arranjar isto, o start arc tem de ser definido algures
              
              %build calibration model
              calmod=calmod.set_cols(i,...
                cal.ac0.cols( param_col)+...
                cal.ac0d.cols(param_col).times(t.ac0d)+...
                cal.ac0q.cols(param_col).times(t.ac0q.^2)...
              );
            end
            %propagate it
            obj=obj.sat_set(dataname.type,dataname.level,levels{l},sats{s},calmod);
          end
        end
      end
    end
    function obj=import_acc_l1b(obj,dataname,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired('dataname',@(i) isa(i,'datanames'));
      p.addParameter('start', obj.start, @(i) isdatetime(i)  &&  isscalar(i));
      p.addParameter('stop',  obj.stop,  @(i) isdatetime(i)  &&  isscalar(i));
      % parse it
      p.parse(dataname,varargin{:});
      % sanity
      if isempty(p.Results.start) || isempty(p.Results.stop)
        error([mfilename,': need ''start'' and ''stop'' parameters (or non-empty obj.start and obj.stop).'])
      end
      %retrieve product info
      product=obj.mdget(dataname);
      %retrieve relevant parameters
      sats =product.mdget('sats');
      indir=product.mdget('import_dir');
      version=product.mdget('version');
      %gather list of daily data files
      [~,timestamplist]=product.file('data',varargin{:},...
        'start',p.Results.start,...
        'stop', p.Results.stop...
      );
      %loop over the satellites
      for s=1:numel(sats)
        infile=cell(size(timestamplist));
        %loop over all dates
        for i=1:numel(timestamplist)
          %build input data filename
          infile{i}=fullfile(indir,datestr(timestamplist(i),'yy'),'acc','asc',...
            ['ACC1B_',datestr(timestamplist(i),'yyyy-mm-dd'),'_',sats{s},'_',version,'.asc']...
          );
        end
        %load (and save the data in mat format, as handled by simpletimeseries.import)
        obj=obj.sat_set(dataname.type,dataname.level,dataname.field,sats{s},...
          simpletimeseries.import(infile,'cut24hrs',false)...
        );
      end
      %make sure start/stop options are honoured (if non-empty)
      if ~isempty(obj)
        obj.start=p.Results.start;
        obj.stop= p.Results.stop;
      end
    end
    function obj=import_acc_mod(obj,dataname,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired('dataname',@(i) isa(i,'datanames'));
      p.addParameter('start', obj.start, @(i) isdatetime(i)  &&  isscalar(i));
      p.addParameter('stop',  obj.stop,  @(i) isdatetime(i)  &&  isscalar(i));
      % parse it
      p.parse(dataname,varargin{:});
      % sanity
      if isempty(p.Results.start) || isempty(p.Results.stop)
        error([mfilename,': need ''start'' and ''stop'' parameters (or non-empty obj.start and obj.stop).'])
      end
      %retrieve product info
      product=obj.mdget(dataname);
      %retrieve relevant parameters
      sats =product.mdget('sats');
      indir=product.mdget('import_dir');
      acc_version =product.mdget('acc_version' );
      gps_version =product.mdget('gps_version' );
      grav_version=product.mdget('grav_version');
      %gather list of daily data files
      [~,timestamplist]=product.file('data',varargin{:},...
        'start',p.Results.start,...
        'stop', p.Results.stop...
      );
      %loop over the satellites
      for s=1:numel(sats)
        infile=cell(size(timestamplist));
        %loop over all dates
        for i=1:numel(timestamplist)
          %build input data filename
          infile{i}=fullfile(indir,datestr(timestamplist(i),'yy'),datestr(timestamplist(i),'mm'),'gps_orb_l',...
            ['grc',sats{s},'_gps_orb_',datestr(timestamplist(i),'yyyy-mm-dd'),...
            '_RL',acc_version,'_GPSRL',gps_version,'_RL',grav_version,'.*.acc']...
          );
        end
        %load (and save the data in mat format, as handled by simpletimeseries.import)
        obj=obj.sat_set(dataname.type,dataname.level,dataname.field,sats{s},...
          simpletimeseries.import(infile,'cut24hrs',true)...
        );
      end
      %make sure start/stop options are honoured (if non-empty)
      if ~isempty(obj)
        obj.start=p.Results.start;
        obj.stop= p.Results.stop;
      end
    end
    function calpar_debug_plots(debug)
      if ~exist('debug','var') || isempty(debug)
        debug=false;
      end
      %get current git version
      [status,timetag]=system(['git log -1 --format=%cd --date=iso-local ',mfilename,'.m']);
      %get rid of timezone and leading trash
      timetag=timetag(9:27);
      %sanity
      assert(status==0,[mfilename,': could not determine git time tag'])
      %create dir for plots
      plot_dir=fullfile('plot','calpar_debug_plots',timetag);
      if isempty(dir(plot_dir)); mkdir(plot_dir); end
      
      %define list of days to plot
      lod=datetime({...
        '2002-08-06',...
        '2002-08-16','2002-08-17',...
        '2003-01-13','2003-01-14',...
        '2003-11-20',...
        '2006-06-14','2006-06-15',...
        '2002-04-15',...
        '2002-08-03',...
        '2002-08-26',...
        '2002-04-27',...
        '2002-09-30'...
      });
      %loop over all requested days
      for i=1:numel(lod)
        start=lod(i);
        stop=lod(i)+days(1)-seconds(1);
        %plot it
        datastorage('debug',debug,'start',start,'stop',stop).init('grace.acc.cal_csr_plots','plot_dir',plot_dir)
      end
    end
  end
end