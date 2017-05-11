% category
% type
% level
% field
% sat

classdef gswarm
  methods(Static)
    function obj=load_models(obj,product,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired('product',@(i) isa(i,'dataproduct'));
      p.addParameter('start', obj.start, @(i) isdatetime(i)  &&  isscalar(i));
      p.addParameter('stop',  obj.stop,  @(i) isdatetime(i)  &&  isscalar(i));
      % parse it
      p.parse(product,varargin{:});
      %retrieve relevant parameters
      model_types       =product.mdget('model_types');
      indir             =product.mdget('import_dir');
      wilcarded_filename=product.mdget('wilcarded_filename');
      model_format      =product.mdget('model_format');
      date_parser       =str2func(product.mdget('date_parser'));
      max_degree        =product.mdget('max_degree');
      use_GRACE_C20     =product.mdget('use_GRACE_C20');
      delete_C00        =product.mdget('delete_C00');
      static_field      =product.mdget('static_model');
      %load all available data 
      [s,e]=gravity.load_dir(indir,model_format,date_parser,...
        'wilcarded_filename',wilcarded_filename,...
        'start',p.Results.start,...
        'stop',p.Results.stop,...
        'descriptor',product.name...
      );
      %enforce consistent GM and R
      s=s.setGM(gravity.default_list.GM);
      s=s.setR( gravity.default_list.R );
      e=e.setGM(gravity.default_list.GM);
      e=e.setR( gravity.default_list.R );
      %set maximum degree (if requested)
      if max_degree>0
        s.lmax=max_degree;
        e.lmax=max_degree;
      end
      %set C20 coefficient
      if use_GRACE_C20
        %some sanity
        if strcmpi(product.mdget('date_parser'),'static')
          error([mfilename,': there''s no point in replacing GRACE C20 coefficients in a static model.'])
        end
        %get C20 timeseries, interpolated to current time domain
        c20=gravity.graceC20.interp(s.t);
%         figure
%         plot(c20.x_masked,c20.y_masked([],1),'x-','MarkerSize',10,'LineWidth',4), hold on
%         plot(c20.x,spline(c20.x_masked,c20.y_masked([],1),c20.x),'o-','MarkerSize',10,'LineWidth',2)
%         plot(c20.x,pchip(c20.x_masked,c20.y_masked([],1),c20.x),'+-','MarkerSize',10,'LineWidth',2)
%         legend('data','spline','pchip')
        %extrapolate in case there are gaps
        if c20.nr_gaps>0
          c20=c20.assign([...
            spline(c20.x_masked,c20.y_masked([],1),c20.x),...
            spline(c20.x_masked,c20.y_masked([],2),c20.x)...
          ],'t',c20.t,'mask',true(size(c20.x)));
        end
        for i=1:s.length
          s=s.setC(2,0,c20.y(i,1),s.t(i));
          e=e.setC(2,0,c20.y(i,2),s.t(i));
        end
%           figure
%           plot(c20.t,c20.y(:,1),'o-'), hold on
%           plot(m.t,m.C(2,0),'x-')
%           legend('GRACE',m.descriptor)
      end
      %remove C00 bias
      if delete_C00
        for i=1:s.length
          s=s.setC(0,0,0);
          e=e.setC(0,0,0);
        end
      end
      %remove static field (if requested)
      if ~strcmpi(static_field,'none')
        %load model (only if not already done)
        if isempty(dir([static_field,'.mat']))
          static=datastorage().init(static_field,'start',s.start,'stop',s.stop);
          save([static_field,'.mat'],'static')
        else
          load([static_field,'.mat'])
        end
        %subtract it
        s=s-static.data_get(static_field).signal;
      end
      %propagate relevant data
      for i=1:numel(model_types)
        switch lower(model_types{i})
        case {'signal','sig','s'}
          obj=obj.sat_set(product.dataname.type,product.dataname.level,product.dataname.field,model_types{i},s);
        case {'error','err','e'}
          obj=obj.sat_set(product.dataname.type,product.dataname.level,product.dataname.field,model_types{i},e);
        otherwise
          error([mfilename,': unknown model type ''',model_types{i},'''.'])
        end
      end
    end
    function obj=smooth_models(obj,product,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired('product',@(i) isa(i,'dataproduct'));
      p.addParameter('start', obj.start, @(i) isdatetime(i)  &&  isscalar(i));
      p.addParameter('stop',  obj.stop,  @(i) isdatetime(i)  &&  isscalar(i));
      % parse it
      p.parse(product,varargin{:});
      %retrieve relevant parameters
      smoothing_degree  =product.mdget('smoothing_degree');
      smoothing_method  =product.mdget('smoothing_method');
      %patch model_types, if not given explicitly
      if product.ismd_field('model_types')
        model_types=product.mdget('model_types','always_cell_array',true);
      else
        model_types={product.dataname.sat};
      end
      %sanity
      assert(product.nr_sources==1,['Can only handle one source model, not ',num2str(product.nr_sources),'.'])
      %gather model  
      m=obj.data_get(product.sources(1).name);
      %apply smoothing
      if smoothing_degree>0
        m=m.scale(smoothing_degree,smoothing_method);
      end
      %propagate relevant data
      for i=1:numel(model_types)
        switch lower(model_types{i})
        case {'error','err','e'}
          obj=obj.sat_set(product.dataname.type,product.dataname.level,product.dataname.field,model_types{i},e);
        otherwise
          obj=obj.sat_set(product.dataname.type,product.dataname.level,product.dataname.field,model_types{i},m);
        end
      end
    end
    function obj=combine_models(obj,product,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired('product',@(i) isa(i,'dataproduct'));
      p.addParameter('start', obj.start, @(i) isdatetime(i)  &&  isscalar(i));
      p.addParameter('stop',  obj.stop,  @(i) isdatetime(i)  &&  isscalar(i));
      % parse it
      p.parse(product,varargin{:});
      %check if data is already in matlab format
      if ~product.isfile('data')
        %retrieve relevant parameters
        combination_type  =product.mdget('combination_type');
        %patch model_types, if not given explicitly
        if product.ismd_field('model_types')
          model_types=product.mdget('model_types','always_cell_array',true);
        else
          model_types={product.dataname.sat};
        end
        %collect the models
        s=cell(product.nr_sources,1);
        e=cell(product.nr_sources,1);
        for i=1:product.nr_sources
          s{i}=obj.data_get([product.sources(i).name,'.signal']);
          e{i}=obj.data_get([product.sources(i).name,'.error']);
        end
        %propagate relevant data
        for i=1:numel(model_types)
          switch lower(model_types{i})
          case {'error','err','e'}
            obj=obj.sat_set(product.dataname.type,product.dataname.level,product.dataname.field,model_types{i},...
              gravity.combine(e,'mode',combination_type,'type','error')...
            );
          otherwise
            obj=obj.sat_set(product.dataname.type,product.dataname.level,product.dataname.field,model_types{i},...
              gravity.combine(s,'mode',combination_type,'type','signal')...
            );
          end
        end
        %save data
        s=obj.data_get(product); %#ok<*NASGU>
        save(char(product.file('data')),'s');
        clear s
      else
        %load data
        load(char(product.file('data')),'s');
        obj=obj.data_set(product,s); %#ok<NODEF>
      end
    end
    function obj=parametric_decomp(obj,product,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired('product',@(i) isa(i,'dataproduct'));
      p.addParameter('start', obj.start, @(i) isdatetime(i)  &&  isscalar(i));
      p.addParameter('stop',  obj.stop,  @(i) isdatetime(i)  &&  isscalar(i));
      % parse it
      p.parse(product,varargin{:});
      %check if data is already in matlab format
      if ~product.isfile('data')
        %sanity
        assert(product.nr_sources==1,...
          [mfilename,': can only operate on a single source, not ',num2str(product.nr_sources),'.']...
        )
        %patch model_types, if not given explicitly
        if product.ismd_field('model_types','always_cell_array',true)
          model_types=product.mdget('model_types');
        else
          model_types={product.dataname.sat};
        end
        %sanity
        assert(numel(model_types)==1 && all(~strcmp(model_types,{'error','err','e'})),...
          [mfilename,': can not operate on models of type ''error''.']...
        )
        polynomial =ones(1,product.mdget('polyorder')+1);
        sinusoidal =time.num2duration(cell2mat(product.mdget('sin_period')),product.mdget('sin_period_unit'));
        if product.ismd_field('t_mod_f')
          t_mod_f=product.mdget('t_mod_f');
        else
          t_mod_f=1;
        end
        %decompose
        s=obj.data_get(...
          [product.sources(1).name,'.signal']...
        ).parametric_decomposition(...
          't_mod_f',t_mod_f,...
          'polynomial',polynomial,...
          'sinusoidal',sinusoidal...
        );
        %propagate relevant data
        obj=obj.field_set(product.dataname.type,product.dataname.level,product.dataname.field,s);
        %save data
        s=obj.data_get(product); %#ok<*NASGU>
        save(char(product.file('data')),'s');
        clear s
      else
        %load data
        load(char(product.file('data')),'s');
        obj=obj.data_set(product,s); %#ok<NODEF>
      end
    end
    function obj=plot_rms_ts(obj,product,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      %parse optional parameters as defined in the metadata
      p=product.plot_args(p,varargin{:});
      %sanity on non-optional parameters
      if ~isa(product,'dataproduct') && ~isscalar(product)
        error([mfilename,': can only handle input ''product'' as scalars of class ''productdata'', not ''',class(in),'''.'])
      end
      %build filename sufix
      if isempty(p.Results.plot_file_suffix)
        suffix='';
      else
        suffix=['.',p.Results.plot_file_suffix];
      end
      %retrive data flow structure
      [~,df]=obj.dataflow(product);
      %gather list of daily data files
      [~,startlist,stoplist]=product.file('data',varargin{:},'start',obj.start,'stop',obj.stop);
      %loop over all data
      for t=1:numel(startlist)
        for i=1:size(df.types,1)
          for j=1:size(df.levels,1)
            for k=1:size(df.fields,1)
              for s=1:size(df.sats,1)
                %get name of current column to plot
                col_names=p.Results.plot_column_names;
                if isempty(col_names)
                  %pick the first input dataname
                  col_names=obj.data_get(...
                    datanames([obj.category,df.types(i,2),df.levels(j,2),df.fields(k,2),df.sats(s,2)])...
                  ).labels;
                end
                %build output datanames
                out_dn=datanames([obj.category,df.types(i,1),df.levels(j,1),df.fields(k,1),df.sats(s,1)]);
                %plot filename arguments
                filename_args=[obj.mdget(out_dn).file_args('plot'),{...
                  'start',startlist(t),...
                  'stop', stoplist(t),...
                  'timestamp',true,...
                  'remove_part','',...
                  'prefix',p.Results.plot_file_prefix,...
                  'suffix',suffix...
                }];
                %plot filename
                filename=out_dn.file(filename_args{:});
                if isempty(dir(filename))
                  %build input datanames
                  in_dn=cell(1,product.nr_sources);
                  for l=1:product.nr_sources
                    in_dn{l}=datanames([obj.category,df.types(i,l+1),df.levels(j,l+1),df.fields(k,l+1),df.sats(s,l+1)]);
                  end
                  %get the data for the current segment
                  obj_curr=obj.trim(startlist(t),stoplist(t));
                  %make sure there is data 
                  if any(cell2mat(obj_curr.vector_sts('nr_valid',in_dn))>1)
                    %remove C00 and C20
                    for ci=1:numel(in_dn)
                      obj_curr=obj_curr.data_set(in_dn{ci},...
                        obj_curr.data_get(in_dn{ci}).setC([0 2],[0 0],[0 0])...
                      );
                    end
                    %need all data to be in the same time domain
                    assert(obj_curr.isteq(in_dn),...
                      [mfilename,': the time domain of the input data is not in agreement.'])
                    %build data array
                    bardat=nan(obj_curr.data_get(in_dn{1}).length,numel(in_dn));
                    for di=1:numel(in_dn)
                      tmp=obj_curr.data_get(in_dn{di}).scale(product.mdget('plot_functional'),'functional').cumdrms;
                      bardat(:,di)=tmp(:,end);
                    end
                    %plot it
                    figure('visible',p.Results.plot_visible);
                    h=bar(datenum(obj_curr.data_get(in_dn{1}).t),bardat);
                    %enforce plot preferences
                    product.enforce_plot
                    %build plot annotation structure
                    bh=cell(size(in_dn));
                    for di=1:numel(in_dn)
                      bh{di}=struct(...
                        'mask',obj_curr.data_get(in_dn{di}).mask,...
                        'y_mean',0,...
                        'handle',bh(i),...
                        'title',in_dn{di}.name,...
                        'xlabel','time',...
                        'ylabel',product.mdget('plot_functional'),...
                        'y_units',gravity.functional_units(product.mdget('plot_functional')),...
                        'legend',{{in_dn{di}.name}}...
                      );
                    end
                    %annotate plot
                    obj.plot_annotate(bh,product.dataname,in_dn,varargin{:})
                    %make xticks show readable time
                    datetick('x',product.mdget('plot_dateformat'))
                    %remove outline
                    set(h,'edgecolor','none')
                    %save this plot
                    saveas(gcf,filename)
                    % user feedback
                    if strcmp(p.Results.plot_visible,'off')
                      disp(['gswarm.plot_rms_ts: plotted ',product.name,' to file ',filename])
                    end
                  else
                    disp(['gswarm.plot_rms_ts: not enough data to plot ',product.name,' to file ',filename,' (skipped)'])
                  end
                end
              end
            end
          end
        end
      end
    end
    function filelist=icgem(obj,product,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired('product',@(i) isa(i,'dataproduct'));
      % parse it
      p.parse(product,varargin{:});
      %retrieve relevant data
      dat=obj.data_get(product);
      %call exporting routine
      filelist=dat.signal.icgem(...
        'prefix',product.name,...
        'path',  product.mdget('export_dir'),...
        'modelname',product.name...
      );
%         'error_obj',dat.error,...
    end
  end
end