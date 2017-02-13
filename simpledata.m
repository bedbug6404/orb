classdef simpledata
  %static
  properties(Constant,GetAccess=private)
    %NOTE: edit this if you add a new parameter
    parameter_list=struct(...
      'peeklength',struct('default',10,     'validation',@(i) isnumeric(i) && iscalar(i)),...
      'labels',    struct('default',{{''}}, 'validation',@(i) iscell(i)),...
      'y_units',   struct('default',{{''}}, 'validation',@(i) iscellstr(i)),...
      'x_units',   struct('default','',     'validation',@(i) ischar(i)),...
      'descriptor',struct('default','',     'validation',@(i) ischar(i)),...
      'plot_zeros',struct('default',true,   'validation',@(i) islogical(i) && isscalar(i))...
    );
    %These parameter are considered when checking if two data sets are
    %compatible (and only these).
    %NOTE: edit this if you add a new parameter (if relevant)
    compatible_parameter_list={'y_units','x_units'};
    %default value of some internal parameters
    default_list=struct(...
      'nSigma',4 ...
    );
  end
  %read only
  %NOTE: edit this if you add a new parameter (if read only)
  properties(SetAccess=private)
    length
    width
    plot_zeros
    x
    y
    mask
  end
  %These parameters should not modify the data in any way; they should
  %only describe the data or the input/output format of it.
  %NOTE: edit this if you add a new parameter (if read/write)
  properties(GetAccess=public,SetAccess=public)
    labels
    y_units
    x_units
    descriptor
    peeklength
  end
  methods(Static)
    function out=valid_x(x)
      out=isnumeric(x) && ~isempty(x) && isvector(x);
    end
    function [x,y,mask]=monotonic(x,y,mask)
      if ~issorted(x)
        [x,idx]=sort(x);
        y=y(idx,:);
        if ~isempty(mask)
          mask=mask(idx);
        end
      end
      %TODO: diff(x) should be one entry smaller than x
      bad_idx=diff(x)<=0;
      if any(bad_idx)
        disp([mfilename,': WARNING: need to remove ',num2str(sum(bad_idx)),' epoch(s) to make abcissae monotonic.'])
        x=x(~bad_idx);
        y=y(~bad_idx,:);
        if ~isempty(mask)
          mask=mask(~bad_idx);
        end
      end
    end
    function out=valid_y(y)
      out=isnumeric(y) && ~isempty(y); % && size(y,1) > size(y,2);
    end
    function out=valid_mask(mask)
      out=islogical(mask) && ~isempty(mask) && isvector(mask);
    end
    function out=default
      out=simpledata.default_list;
    end
    function out=parameters
      out=fieldnames(simpledata.parameter_list);
    end
    function out=vararginclean(in,parameters)
      out=in;
      for i=1:numel(parameters)
        idx=0;
        for j=1:2:numel(out)
          if strcmp(out{j},parameters{i})
            idx=j;
            break
          end
        end
        if idx>0
          out=out([1:j-1,j+2:end]);
        end
      end
    end
    function [x,varargout] = union(x1,x2,tol)
      %If x1 and x2 are (for example) time domains, with each entry being a time
      %value, x is the vector of entries in either <x1> or <x2>.
      %
      %<indx1> and <indx2> have the indexes that relate <x> to <x1> and <x2>, so
      %that:
      %
      %x(ind1) = x1;
      %x(ind2) = x2;
      %
      %All outputs are column vectors.
      %
      %This is an OR operation, x has elements of any x1 or x2.
      %
      %A practical application for this would be to reconstruct a signal that is
      %measured with two sensors, each in its own time domain.
      %
      % t1 = [1 2 3 4 5 6];
      % s1 = sin(t1);
      % t2 = [0 1.5 3 4.5 6 7.5];
      % s2 = sin(t2);
      % [t,i1,i2] = union(t1,t2);
      % s(i1) = s1;
      % s(i2) = s2;
      % plot(t1,s1,'bo',t2,s2,'ro',t,s)
      
      %trivial call
      if isempty(x1) || isempty(x2)
        x = [];
        varargout={[],[]};
        return
      end
      if ~exist('tol','var') || isempty(tol)
        tol=1e-6;
      end
      %sanity
      if ~isvector(x1) || ~isvector(x2)
        error([mfilename,': inputs <x1> and <x2> must be 1D vectors.']);
      end
      if (isnumeric(x1) && any(isnan(x1))) || ...
         (isnumeric(x2) && any(isnan(x2)))
        error([mfilename,': cannot handle NaNs in the input arguments. Clean them first.'])
      end
      %shortcuts
      if numel(x1)==numel(x2) && all(x1(:)==x2(:))
        x=x1;
        varargout={true(size(x1)),true(size(x2))};
        return
      end
      %get first output argument (need to use tolerance to captures time system conversion errors)
      xt=[x1(:);x2(:)];
      tol=tol/max(abs(xt));
      x=uniquetol(xt,tol);
      %maybe we're done here
      if nargout==1
        return
      end
      %get second argument
      varargout(1)={ismembertol(x,x1,tol)};
      %maybe we're done here
      if nargout==2
        return
      end
      %get third argument
      varargout(2)={ismembertol(x,x2,tol)};
      %now we're done for sure
      return
    end
    function [out,idx]=rm_outliers(in,varargin)
      % NOTE: greatly simplified the version of this routine described below:
      %
      % [OUT,IDX,STD_ERR]=NUM_RM_OUTLIERS(IN,NSIGMA,SMOOTH_METHOD,SPAN_FACTOR,PLOTFLAG)
      % is an outlier detection routine. It looks at the points in IN and flags
      % the ones that deviate from the reference by NSGIMA*std as outliers.
      % OUT is equal to IN, with NaN's replacing the flagged outliers. IDX is
      % a logical mask which contains indexes of IN flagged as outliers.
      %
      %   NUM_RM_OUTLIERS(IN) removes the outliers in input IN using default
      %   settings.
      %
      %   NUM_RM_OUTLIERS(IN,NSIGMA) additionally specifies how many
      %   times bigger than the STD are the outliers. Default value is 4.
      %
      %   NUM_RM_OUTLIERS(IN,NSIGMA,METHOD,SPAN_FACTOR) can be used to specify
      %   different methods of outlier detection. In general an outlier can be
      %   seen as a data-point which deviates from a certain reference by a
      %   statistical limit. The reference taken depends greatly on the type of
      %   input signal IN. If IN is a random zero-mean process than outliers
      %   can be computed by the distance to the x-axis. However if IN is a noisy
      %   sinusoidal signal the above reference (x-axis) result in cropping
      %   the wave at min and max regions. For that reason different methods
      %   are available to defined the reference points,
      %   The following methods are available,
      %   'zero'    - Outliers referenced to the x-axis.
      %   'mean'    - Outliers referenced to the mean of the signal [default]
      %   'detrend' - Outliers referenced to the best fitting line to IN
      %   'polyfit' - Outliers referenced to the best fitting polynom of degree
      %               POLYDEGREE. This method requires the additional input:
      %       NUM_RM_OUTLIERS(IN,NSIGMA,METHOD,POLYDEGREE)
      %
      %   Additional methods are available throught the internal use of the
      %   'smooth' function. There are 'moving','lowess','loess','sgolay',
      %   'rlowess','rloess'. For all these methods an additional input SPAN is
      %   required,
      %       [OUT,IDX]=NUM_RM_OUTLIERS(IN,NSIGMA,METHOD,SPAN) which specifies
      %   the length SPAN of the smoothing window relative to the lenght of
      %   the input. The default span is 0.1. Negative values of SPAN are also
      %   possible and they are implemented to allow the user to set a SPAN
      %   which is independent of the signal length.
      %
      %   NUM_RM_OUTLIERS(...,PLOTFLAG) with PLOTFLAG set to 'true' or to a
      %   figure handle will plot the flagged outliers and the reference signal.

      % Created by J.Encarnacao <J.G.deTeixeiradaEncarnacao@tudelft.nl>
      % List of Changes:
      %   Pedro Inacio <p.m.g.inacio@tudelft.nl>, reorganized outlier detection
      %       routine.

      % Handle Inputs
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 'in',                                      @(i) isnumeric(i));
      p.addParameter('nSigma',        simpledata.default.nSigma,@(i) isnumeric(i) &&  isscalar(i));
      p.addParameter('outlier_value', nan,                      @(i) isnumeric(i) &&  isscalar(i));
      % parse it
      p.parse(in,varargin{:});
      %assume there are no outliers
      out=in;
      idx=false(size(in));
      %ignore non-positive nSigmas
      if p.Results.nSigma>0 && numel(in)>1
        % ignore NaNs
        nanidx = isnan(in(:));
        % make aux containers with the same size as input
        err=zeros(size(in));
        % compute error
        err(~nanidx) = in(~nanidx)-mean(in(~nanidx));
        std_err = std(err(~nanidx));
        %trivial call
        if std_err>0
          %outlier indexes
          idx = abs(err)>p.Results.nSigma*std_err;
          %flag outliers
          out(idx(:))=p.Results.outlier_value;
        end
      end
    end
    function obj_list=merge_multiple(obj_list,msg)
      %sanity
      if ~iscell(obj_list)
        error([mfilename,': need input ''obj_list'' to be a cell array, not a ',class(obj_list),'.'])
      end
      % save timing info
      if ~exist('msg','var') || isempty(msg)
        s.msg='merge   op';
      else
        s.msg=['merge   op for ',msg];
      end
      s.n=2*(numel(obj_list)-1); c=0;
      %forward merge
      for i=1:numel(obj_list)-1
        [obj_list{i},obj_list{i+1}]=obj_list{i}.merge(obj_list{i+1});
        c=c+1;s=time.progress(s,c);
      end
      %backward merge
      for i=numel(obj_list):-1:2
        [obj_list{i},obj_list{i-1}]=obj_list{i}.merge(obj_list{i-1});
        c=c+1;s=time.progress(s,c);
      end
    end
    function out=isequal_multiple(obj_list,columns,msg)
      %sanity
      if ~iscell(obj_list)
        error([mfilename,': need input ''obj_list'' to be a cell array, not a ',class(obj_list),'.'])
      end
      % save timing info
      if ~exist('msg','var') || isempty(msg)
        s.msg='isequal op';
      else
        s.msg=['isequal op for ',msg];
      end
      s.n=numel(obj_list)-1; c=0;
      %declare type of output argument
      out=cell(numel(obj_list)-1,1);
      %loop over obj list
      for i=1:numel(obj_list)-1
        out{i}=obj_list{i}.isequal(obj_list{i+1},columns); 
        c=c+1;s=time.progress(s,c);
      end
    end
    function out=stats2(obj1,obj2,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addParameter('mode',   'struct', @(i) ischar(i));
      p.addParameter('minlen', 2,        @(i) isscalar(i));
      p.addParameter('outlier',0,        @(i) isfinite(i));
      p.addParameter('nsigma', simpledata.default.nSigma, @(i) isnumeric(i));
      p.addParameter('struct_fields',...
        {'cov','corrcoef'},...
        @(i) iscellstr(i)...
      )
      % parse it
      p.parse(varargin{:});
      %need compatible objects
      compatible(obj1,obj2)
      %remove outliers
      for i=1:p.Results.outlier
        obj1=obj1.outlier(p.Results.nsigma);
        obj2=obj2.outlier(p.Results.nsigma);
      end
      %need the x-domain and masks to be identical
      [obj1,obj2]=merge(obj1,obj2);
      [obj1,obj2]=mask_match(obj1,obj2);
      %trivial call
      switch p.Results.mode
      case {'cov','corrcoef'}
        %bad things happend when deriving statistics of zero or one data points
        if size(obj1.y_masked,1)<=max([2,p.Results.minlen]);
          out=nan(1,obj1.width);
          return
        end
      end
      %branch on mode
      switch p.Results.mode
      case 'cov'
        out=num.cov(obj1.y_masked,obj1.y_masked);
      case 'corrcoef'
        out=num.corrcoef(obj1.y_masked,obj2.y_masked);
      case 'length';
        out=size(obj1.y_masked,1)*ones(1,obj1.width); %could also be obj2
      case 'struct'
        for f=p.Results.struct_fields;
          out.(f{1})=simpledata.stats2(obj1,obj2,'mode',f{1},'outlier',0);
        end
      otherwise
        error([mfilename,': unknown mode.'])
      end
      %bug traps
      if ~(isstruct(out) || ischar(out)) && any(isnan(out(:)))
          error([mfilename,': detected NaN in <out>. Debug needed.'])
      end
    end
    %general test for the current object
    function out=test_parameters(field,varargin)
      %basic parameters
      switch field
      case 'l'; out=100; return
      case 'w'; out=4;   return
      end
      %optional parameters
      switch numel(varargin)
      case 0
        l=simpledata.test_parameters('l');
        w=simpledata.test_parameters('w');
      case 1
        l=varargin{1};
        w=simpledata.test_parameters('w');
      case 2
        l=varargin{1};
        w=varargin{2};
      end
      %more parameters
      switch field
      case 'args'
        out={...
          'y_units',   strcat(cellstr(repmat('y_unit-',w,1)),cellstr(num2str((1:w)'))),...
          'labels',    strcat(cellstr(repmat('label-', w,1)),cellstr(num2str((1:w)'))),...
          'x_unit',    'x_unit',...
          'descriptor','descriptor'...
        };
      case 'y'
        out=ones(l,1)*randn(1,w)*10+randn(l,w)+(1:l)'*randn(1,w)*0.1;
      case 'mask'
        out=rand(l,1)<0.8;
      case 'no-mask'
        out=true(l,1);
      case 'columns'
        out=[1,find(randn(1,w-1)>0)+1];
      case 'obj'
        args=simpledata.test_parameters('args',l,w);
        out=simpledata(1:l,simpledata.test_parameters('y',l,w),...
          'mask',simpledata.test_parameters('no-mask',l,w),...
          args{:}...
        );
      otherwise
        error([mfilename,': cannot understand field ''',field,'''.'])
      end
    end
    function test(l,w)
      if ~exist('l','var') || isempty(l)
        l=simpledata.test_parameters('l');
      end
      if ~exist('w','var') || isempty(w)
        w=simpledata.test_parameters('w');
      end
         args=simpledata.test_parameters('args',l,w);
      columns=simpledata.test_parameters('columns',l,w);

      i=0;
      
      i=i+1;h{i}=figure('visible','off');
      a=simpledata(1:l,simpledata.test_parameters('y',l,w),...
        'mask',simpledata.test_parameters('no-mask',l,w),...
        args{:}...
      );
      a.plot('columns', columns)
      title('starting point')

      i=i+1;h{i}=figure('visible','off');
      a=a.append(...
        simpledata(-l:0,simpledata.test_parameters('y',l+1,w),...
          'mask',simpledata.test_parameters('mask',l+1,w),...
          args{:}...
        )...
      );
      a.plot('columns', columns)
      title('append')

      lines1=cell(size(columns));lines1(:)={'-o'};
      lines2=cell(size(columns));lines2(:)={'-x'};
      i=i+1;h{i}=figure('visible','off');
      a.median(10).plot('columns', columns,'line',lines1);
      a.medfilt(10).plot('columns', columns,'line',lines2);
      legend('median','medfilt')
      title('median (operation not saved)')
      
      i=i+1;h{i}=figure('visible','off');
      a=a.trim(...
        round(-l/2),...
        round( l/3)...
      );
      a.plot('columns', columns)
      title('trim')
    
      i=i+1;h{i}=figure('visible','off');
      a=a.slice(...
        round(-l/20),...
        round( l/30)...
      );
      a.plot('columns', columns)
      title('delete')
          
      i=i+1;h{i}=figure('visible','off');
      a.interp(...
        round(-l/2):0.4:round(l/3),'interp_over_gaps_narrower_than',0 ...
      ).plot('columns',1,'line',{'x-'});
      hold on
      a.plot('columns',1,'line',{'o:'});
      title('linear interp over gaps narrower than=0')

      i=i+1;h{i}=figure('visible','off');
      a.interp(...
        round(-l/2):0.4:round(l/3),'interp_over_gaps_narrower_than',inf ...
      ).plot('columns',1,'line',{'x-'});
      hold on
      a.plot('columns',1,'line',{'o:'});
      title('spline interp over gaps narrower than \infty')

      i=i+1;h{i}=figure('visible','off');
      a.interp(...
        round(-l/2):0.4:round(l/3),'interp_over_gaps_narrower_than',3 ...
      ).plot('columns',1,'line',{'x-'});
      hold on
      a.plot('columns',1,'line',{'o:'});
      title('spline interp over gaps narrower than 2')
      
      i=i+1;h{i}=figure('visible','off');
      a=a.detrend;
      a.plot('columns', columns);
      title('detrended')

      i=i+1;h{i}=figure('visible','off');
      a.plot('columns', 1,'line',{'x-'});
      [a,o]=a.outlier(2);
      a.plot(...
        'columns', 1,...
        'masked',true,...
        'line',{'+'}...
      );
      o.plot(...
        'columns', 1,...
        'masked',true,...
        'line',{'o'}...
      );
      title('detrended without outliers')
      legend('original','w/out outliers','outliers')
      
      i=i+1;h{i}=figure('visible','off');
      a=simpledata(0:l,simpledata.test_parameters('y',l+1,w),...
        'mask',[true(0.2*l+1,1);false(0.2*l,1);true(0.6*l,1)],...
        args{:}...
      );
      b=simpledata(-l/2:2:3/2*l,simpledata.test_parameters('y',l+1,w),...
        'mask',[true(0.3*l+1,1);false(0.2*l,1);true(0.2*l,1);false(0.1*l,1);true(0.2*l,1)],...
        args{:}...
      );
      a.plot('column',1,'line',{'+-'})
      b.plot('column',1,'line',{'x-'})
      c=a+b;
      c.plot('column',1,'line',{'o-'})
      legend('a','b','a+b')
      title('add two series')
    
      for i=numel(h):-1:1
        set(h{i},'visible','on')
      end
    end
  end
  methods
    %% constructor
    function obj=simpledata(x,y,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 'x'      ,                  @(i) simpledata.valid_x(i));
      p.addRequired( 'y'      ,                  @(i) simpledata.valid_y(i));
      p.addParameter('mask'   ,true(size(x(:))), @(i) simpledata.valid_mask(i));
      %declare parameters
      for j=1:numel(simpledata.parameters)
        %shorter names
        pn=simpledata.parameters{j};
        %declare parameters
        p.addParameter(pn,simpledata.parameter_list.(pn).default,simpledata.parameter_list.(pn).validation)
      end
      % parse it
      p.parse(x(:),y,varargin{:});
      % save parameters
      for i=1:numel(simpledata.parameters)
        %shorter names
        pn=simpledata.parameters{i};
        if ~isscalar(p.Results.(pn))
          %vectors are always lines (easier to handle strings)
          obj.(pn)=transpose(p.Results.(pn)(:));
        else
          obj.(pn)=p.Results.(pn);
        end
      end
      % check parameters
      for i=1:numel(simpledata.parameters)
        obj=check_annotation(obj,simpledata.parameters{i});
      end
      %assign
      obj=obj.assign(y,'x',x,varargin{:});
    end
    function obj=assign(obj,y,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 'y'          ,         @(i) simpledata.valid_y(i));
      p.addParameter('x'          ,obj.x,   @(i) simpledata.valid_x(i));
      p.addParameter('mask'       ,obj.mask,@(i) simpledata.valid_mask(i));
      p.addParameter('reset_width',false,   @(i) isscalar(i));
      % parse it
      p.parse(y,varargin{:});
      % ---- x ----
      if numel(p.Results.x)~=size(y,1)
        error([mfilename,': number of elements of input ''x'' (',num2str(numel(p.Results.x)),...
          ') must be the same as the number of rows of input ''y'' (',num2str(size(y,1)),').'])
      end
      %propagate x
      obj.x=p.Results.x(:);
      %update length
      obj.length=numel(obj.x);
      % ---- y ----
      if ~logical(p.Results.reset_width) && ~isempty(obj.width) && size(y,2) ~= obj.width
        error([mfilename,': data width changed from ',num2str(obj.width),' to ',num2str(size(y,2)),'.'])
      end
      if obj.length~=size(y,1)
        error([mfilename,': data length different than size(y,2), i.e. ',...
          num2str(obj.length),' ~= ',num2str(size(y1m)),'.'])
      end
      %update width
      obj.width=size(y,2);
      %propagate y
      obj.y=y;
      % ---- mask ----
      if obj.length==numel(p.Results.mask)
        %propagate mask
        obj.mask=p.Results.mask(:);
      else
        if ~any(strcmp(p.UsingDefaults,'mask'))
          error([mfilename,': number of elements of input ''mask'' (',num2str(numel(p.Results.mask)),...
            ') must be the same as the data length (',num2str(obj.length),').'])
        end
        %using default mask, data length may have changed: set mask from y
        obj=obj.mask_reset;
      end
      %sanitize done inside mask_update
      obj=mask_update(obj);
    end
    function obj=copy_metadata(obj,obj_in)
      parameters=fieldnames(simpledata.parameter_list);
      for i=1:numel(parameters)
        if isprop(obj,parameters{i}) && isprop(obj_in,parameters{i})
          obj.(parameters{i})=obj_in.(parameters{i});
        end
      end      
    end
    function obj_nan=nan(obj)
      %duplicates an object, setting y to nan
      obj_nan=obj.and(false(size(obj.mask))).mask_update;
    end
    %% info methods
    function print(obj,tab)
      if ~exist('tab','var') || isempty(tab)
        tab=12;
      end
      %parameters
      for i=1:numel(simpledata.parameters)
        obj.disp_field(simpledata.parameters{i},tab);
      end
      %some parameters are not listed
      more_parameters={'length','width'};
      for i=1:numel(more_parameters)
        obj.disp_field(more_parameters{i},tab);
      end
      %add some more info
      obj.disp_field('nr gaps',    tab,sum(~obj.mask))
      obj.disp_field('first datum',tab,sum(obj.x(1)))
      obj.disp_field('last datum', tab,sum(obj.x(end)))
      if obj.width<10
        obj.disp_field('statistics', tab,[10,stats(obj,'mode','str-nl','tab',tab,'period',inf)])
      end
      obj.peek
    end
    function disp_field(obj,field,tab,value)
      if ~exist('value','var') || isempty(value)
        value=obj.(field);
      end
      disp([str.tabbed(field,tab),' : ',str.show(transpose(value(:)))])
    end
    function peek(obj,idx,tab)
      if ~exist('tab','var') || isempty(tab)
        tab=12;
      end
      if ~exist('idx','var') || isempty(idx)
        if isempty(obj.peeklength)
          obj.peeklength=simpledata.parameter_list.peeklength.default;
        end
        idx=[...
          1:min([           obj.peeklength,  round(0.5*obj.length)  ]),...
            max([obj.length-obj.peeklength+1,round(0.5*obj.length)+1]):obj.length...
        ];
      end
      for i=1:numel(idx)
        out=cell(1,obj.width);
        for j=1:numel(out)
          out{j}=str.tabbed(num2str(obj.y(idx(i),j)),tab,true);
        end
        %use formatted dates is object supports them
        if ismethod(obj,'t')
          x_str=datestr(obj.t(idx(i)),'yyyy-mm-dd HH:MM:SS');
        else
          x_str=num2str(obj.x(idx(i)));
        end
        disp([...
          str.tabbed(x_str,tab,true),' ',...
          strjoin(out),' ',...
          str.show(obj.mask(idx(i)))...
        ])
      end
    end
    function out=stats(obj,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addParameter('mode',   'struct', @(i) ischar(i));
      p.addParameter('frmt',   '%-16.3g',@(i) ischar(i));
      p.addParameter('tab',    8,        @(i) isscalar(i));
      p.addParameter('minlen', 2,        @(i) isscalar(i));
      p.addParameter('outlier',0,        @(i) isfinite(i));
      p.addParameter('nsigma', simpledata.default.nSigma, @(i) isnumeric(i));
      p.addParameter('columns', 1:obj.width,@(i)isnumeric(i) || iscell(i));
      p.addParameter('struct_fields',...
        {'min','max','mean','std','rms','meanabs','stdabs','rmsabs','length','gaps'},...
        @(i) iscellstr(i)...
      )
      % parse it
      p.parse(varargin{:});
      %remove outliers
      for c=1:p.Results.outlier
        obj=obj.outlier(p.Results.nsigma);
      end
      %trivial call
      switch p.Results.mode
      case {'min','max','mean','std','rms','meanabs','stdabs','rmsabs'}
        %bad things happend when deriving statistics of zero or one data points
        if size(obj.y_masked,1)<max([2,p.Results.minlen]);
          out=nan(1,obj.width);
          return
        end
      end
      % type conversions
      if iscell(p.Results.columns)
        columns=cell2mat(p.Results.columns);
      else
        columns=p.Results.columns;
      end
      %branch on mode
      switch p.Results.mode
      case 'min';     out=min(     obj.y_masked([],columns));
      case 'max';     out=max(     obj.y_masked([],columns));
      case 'mean';    out=mean(    obj.y_masked([],columns));
      case 'std';     out=std(     obj.y_masked([],columns));
      case 'rms';     out=rms(     obj.y_masked([],columns));
      case 'meanabs'; out=mean(abs(obj.y_masked([],columns)));
      case 'stdabs';  out=std( abs(obj.y_masked([],columns)));
      case 'rmsabs';  out=rms( abs(obj.y_masked([],columns)));
      case 'length';  out=size(    obj.y_masked,1)*ones(1,obj.width);
      case 'gaps';    out=sum(    ~obj.mask)*ones(1,obj.width);
      %one line, two lines, three lines, many lines
      case {'str','str-2l','str-3l','str-nl'} 
        out=cell(size(p.Results.struct_fields));
        for i=1:numel(p.Results.struct_fields);
          out{i}=[...
            str.tabbed(p.Results.struct_fields{i},p.Results.tab),' : ',...
            num2str(...
            stats@simpledata(obj,varargin{:},'mode',p.Results.struct_fields{i}),...
            p.Results.frmt)...
          ];
        end
        %concatenate all strings according to the required mode
        switch p.Results.mode
        case 'str'
          out=strjoin(out,'; ');
        case 'str-2l'
          mid_idx=ceiling(numel(out)/2);
          out=[...
            strjoin(out(1:mid_idx),'; '),...
            10,...
            strjoin(out(mid_idx+1:end),'; ')...
            ];
        case 'str-3l'
          mid_idx=ceiling(numel(out)/3);
          out=[...
            strjoin(out(1:mid_idx),'; '),...
            10,...
            strjoin(out(mid_idx+1:2*mid_idx),'; '),...
            10,...
            strjoin(out(2*mid_idx+1:end),'; ')...
            ];
        case 'str-nl'
          out=strjoin(out,'\n');
        end
      case 'struct'
        for f=p.Results.struct_fields;
          out.(f{1})=stats@simpledata(obj,varargin{:},'mode',f{1});
        end
      otherwise
        error([mfilename,': unknown mode.'])
      end
      %bug traps
      if isnumeric(out)
        if any(isnan(out(:)))
          error([mfilename,': BUG TRAP: detected NaN in <out>. Debug needed.'])
        end
        if size(out,2)~=numel(columns)
          error([mfilename,': BUG TRAP: data width changed. Debug needed.'])
        end
      end
    end
    %% x methods
    function out=x_masked(obj,mask)
      if ~exist('mask','var') || isempty(mask)
        mask=obj.mask;
      end
      out=obj.x(mask);
    end
    function obj=x_set(obj,in)
      if ~simpledata.valid_x(in) || numel(in) ~= obj.length
        error([mfilename,': invalid input ''in''.'])
      end
      obj.x=in;
    end
    function out=idx(obj,x_now,varargin)
      % sanity
      assert(isvector( x_now),[mfilename,': Input x_now must be a vector.'])
      assert(isnumeric(x_now),[mfilename,': Input x_now must be numeric, not ',class(x_now),'.'])
      if numel(x_now)>1
        %making room for outputs
        out=NaN(size(x_now));
        %recursive call
        for i=1:numel(x_now)
          out(i)=obj.idx(x_now(i),varargin{:});
        end
      else
        %compute distance to input
        distance=(obj.x-x_now).^2;
        %handle default find arguments
        if isempty(varargin)
          out=find(distance==min(distance),1,'first');
        else
          out=find(distance==min(distance),varargin{:});
        end
      end
    end
    function obj=at(obj,x_now,varargin)
      i=obj.idx(x_now,varargin{:});
      obj=obj.assign(...
        obj.y(i,:),...
        'x',obj.x(i,:),...
        'mask',obj.mask(i,:)...
      );
    end
    function [obj,idx_add,idx_old,x_old]=x_merge(obj,x_add)
      %add epochs given in x_add, the corresponding y are NaN and mask are set as gaps
      if nargout==4
        %save x_old
        x_old=obj.x;
      end
      %build extended x-domain
      [x_total,idx_old,idx_add] = simpledata.union(obj.x,x_add);
      %shortcut
      if all(idx_old) && all(idx_add)
        return
      end
      %build extended y and mask
      y_total=NaN(numel(x_total),obj.width);
      y_total(idx_old,:)=obj.y;
      mask_total=false(size(x_total));
      mask_total(idx_old)=obj.mask;
      %sanitize monotonicity and propagate
      [x_total,y_total,mask_total]=simpledata.monotonic(x_total,y_total,mask_total);
      %propagate to obj
      obj=obj.assign(y_total,'x',x_total,'mask',mask_total);
    end
    %% y methods
    function obj=cols(obj,columns)
      if ~isvector(columns)
        error([mfilename,': input ''columns'' must be a vector'])
      end
      %update width
      obj.width=numel(columns);
      %retrieve requested columns
      obj.y      =obj.y(:,    columns);
      obj.labels =obj.labels( columns);
      obj.y_units=obj.y_units(columns);
    end
    function obj=get_cols(obj,columns)
      obj=obj.cols(columns);
    end
    function obj=set_cols(obj,columns,values)
      y_now=obj.y;
      if isnumeric(values)
        y_now(:,columns)=values;
      else
        y_now(:,columns)=values.y;
      end
      obj=obj.assign(y_now);
    end
    function out=y_masked(obj,mask,columns)
      if ~exist('mask','var') || isempty(mask)
        mask=obj.mask;
      end
      if ~exist('columns','var') || isempty(columns)
        columns=1:obj.width;
      end
      if ~isvector(columns)
        error([mfilename,': input ''columns'' must be a vector'])
      end
      if any(columns>obj.width)
        error([mfilename,': requested column indeces exceed object width.'])
      end
      out=obj.y(mask,columns);
    end
    %% mask methods
    %NOTICE: these functions only deal with *explicit* gaps, i.e. those in
    %the form of:
    %x=[1,2,3,4,5..], mask=[T,T,F,T,T...] (x=3 being an explict gap).
    %in comparison, implicit gaps are:
    %x=[1,2,4,5..], mask=[T,T,T,T...] (x=3 being an implict gap).
    function obj=mask_and(obj,mask_now)
      %NOTE: this calls set.mask (and mask_update as well)
      obj.mask=obj.mask & mask_now(:);
    end
    function obj=mask_or(obj,mask_now)
      %NOTE: this calls set.mask (and mask_update as well)
      obj.mask=obj.mask | mask_now(:);
    end
    function obj=mask_update(obj)
      %sanity
      if numel(obj.mask) ~= size(obj.y,1)
        error([mfilename,': sizes of mask and y are not in agreement.'])
      end
      %propagate gaps from and to mask
      obj.mask=obj.mask & all(~isnan(obj.y),2);
      obj.y(~obj.mask,:)=NaN;
      %sanitize
      obj.check_sd
    end
    function obj=mask_reset(obj)
      obj.mask=all(~isnan(obj.y),2);
    end
    function [out,nr_epochs]=gap_length(obj)
      %inits
            out=zeros(obj.length,1);
      nr_epochs=zeros(obj.length,1);
      gap_length=0;
      gaps_start_idx=0;
      %go through the mask
      for i=1:obj.length
        %check for gap
        if ~obj.mask(i)
          %increment counters
          gap_length=gap_length+1;
          %init start index (unless already done)
          if gaps_start_idx==0
            gaps_start_idx=i;
          end
        else
          %check if coming out of a gap
          if gap_length>0
            idx=gaps_start_idx:i-1;
            %save gap length and nr of gaps
                  out(idx)=obj.x(i)-obj.x(max([1,gaps_start_idx-1]));
            nr_epochs(idx)=gap_length;
            %reset counters
            gap_length=0;
            gaps_start_idx=0;
          end
        end
      end
      %save gap length at the end of the x-domain
      if gap_length>0
        idx=gaps_start_idx:obj.length;
        %save gap length and nr of gaps
              out(idx)=obj.x(end)-obj.x(gaps_start_idx-1);
        nr_epochs(idx)=gap_length;
      end
      %sanity
      if any(out(obj.mask)~=0)
        error([mfilename,': found non-zero gaps lengths outside of gaps. Debug needed!'])
      end
      if any(out(~obj.mask)==0)
        error([mfilename,': found zero lengths inside of gaps. Debug needed!'])
      end
    end
    function out=nr_gaps(obj)
      out=sum(~obj.mask);
    end
    function out=nr_valid(obj)
      out=sum(obj.mask);
    end
    function [obj1,obj2]=mask_match(obj1,obj2)
      obj1=obj1.mask_and(obj2.mask);
      obj2=obj2.mask_and(obj1.mask);
      obj1=obj1.mask_update;
      obj2=obj2.mask_update;
    end
    %% management methods
    function check_sd(obj)
      %sanitize
      if obj.length~=numel(obj.x)
        error([mfilename,': discrepancy in length of x'])
      end
      if obj.length~=numel(obj.mask)
        error([mfilename,': discrepancy in length of mask'])
      end
      if obj.length~=size(obj.y,1)
        error([mfilename,': discrepancy in length of y'])
      end
      if obj.width~=size(obj.y,2)
        error([mfilename,': discrepancy in width of y'])
      end
      if any(~all(isnan(obj.y),2)~=obj.mask)
        error([mfilename,': discrepancy between mask and NaNs in y.'])
      end
      if any(isnan(obj.y),2)~=all(isnan(obj.y),2)
        error([mfilename,': found epochs with some components of y as NaNs.'])
      end
    end
    function obj=check_annotation(obj,annotation_name)
      check=true;
      if ~isempty(obj.width) && ...
          iscell(obj.(annotation_name)) && ...
          obj.width~=numel(obj.(annotation_name))
        if  numel(obj.(annotation_name))==1 && ...
          isempty(obj.(annotation_name){1})
          %annotation is cell, with unit length and that entry is empty,
          %i.e. the default is still there. Reset according to width
          obj.(annotation_name)=cell(obj.width,1);
        else
          check=false;
        end
      end
      if ~check
        error([mfilename,': discrepancy in between length of ',annotation_name,' and of width of y'])
      end 
    end
    %% edit methods
    function obj=remove(obj,rm_mask)
      %remove epochs given in rm_mask, by eliminating them from the data, 
      %not by setting them as gaps.
      obj=obj.assign(obj.y(~rm_mask,:),'x',obj.x(~rm_mask),'mask',obj.mask(~rm_mask));
    end
    function obj=trim(obj,start,stop)
      %trim data outside start/stop
      if start>stop
        error([mfilename,': input ''start'' must refer to an abcissae before input ''stop''.'])
      end
      obj=obj.remove(obj.x < start | stop < obj.x);
    end
    function obj=slice(obj,start,stop)
      %delete data between start/stop
      if start>stop
        error([mfilename,': input ''start'' must refer to a abcissae before input ''stop''.'])
      end
      obj=obj.remove(start < obj.x & obj.x < stop);
      %add gap extremities
      gap_extremities=obj.idx([start,stop]);
      obj.y(   gap_extremities,:)=NaN;
      obj.mask(gap_extremities)=false;
    end
    function obj=interp(obj,x_now,varargin)
      % parse inputs
      p=inputParser;
      p.KeepUnmatched=true;
      p.addParameter('interp_over_gaps_narrower_than',0,@(i) isscalar(i) && isnumeric(i) && ~isnan(i))
      p.addParameter('interp1_args',cell(0),@(i) iscell(i))
      % parse it
      p.parse(varargin{:});
      % need to add requested x-domain, so that implicit gaps can be handled
      %NOTICE: x_now = obj.x(idx_now)
      [obj,idx_now]=obj.x_merge(x_now);
      %interpolate over all gaps, use all available information
      switch numel(obj.x_masked)
      case 0
        y_now=nan(numel(x_now),obj.width);
      case 1
        y_now=ones(numel(x_now),1)*obj.y_masked;
      otherwise
        y_now=interp1(obj.x_masked,obj.y_masked,x_now(:),p.Results.interp1_args{:});
      end
      % create mask with requested gap interpolation scheme
      if p.Results.interp_over_gaps_narrower_than <= 0
        %this interpolates over all gaps, i.e. keeps all interpolated data,
        %bridging over gaps of any size
        mask_now=true(size(x_now(:)));
      elseif ~isfinite(p.Results.interp_over_gaps_narrower_than)
        %this keeps all gaps, i.e. only those points wich are common on
        %both x-domains AND are not gaps will appear in the ouput
        mask_now=obj.mask(idx_now);
      else
        %compute gap length and create a mask from that, i.e. it is
        %possible to control the maximum length of a gap in the output
        mask_add=obj.gap_length<p.Results.interp_over_gaps_narrower_than;
        mask_now=mask_add(idx_now);
      end
      % handle empty data
      if sum(mask_now)<1
        obj=obj.assign(nan(size(obj.y)));
        return
      end
      %propagate requested x-domain only (mask is rebuilt from NaNs in 
      obj=obj.assign(y_now,'x',x_now,'mask',mask_now);
    end
    function obj=detrend(obj,mode)
      if ~exist('mode','var') || isempty(mode)
        mode='linear';
      end
      switch mode
      case 'linear'
        %copy data
        y_now=obj.y;
        %zero the gaps (NaNs break things)
        y_now(~obj.mask,:)=0;
        %detrend in segments
        y_detrended=detrend(y_now,'linear',find(~obj.mask));
        %propagate
        obj.y(obj.mask,:)=y_detrended(obj.mask,:);
      case ('constant')
        obj.y(obj.mask,:)=detrend(obj.y_masked,'constant');
      otherwise
        error([mfilename,': unknown mode ''',mode,'''.'])
      end
      % sanitize
      obj.check_sd
    end
    function [obj,outliers]=outlier(obj,nSigma)
      %handle inputs
      if ~exist('nSigma','var') || isempty(nSigma)
        nSigma=simpledata.default.nSigma;
      end
      if ~isnumeric(nSigma)
        error([mfilename,': input <nSigma> must be numeric, not ',class(nSigma),'.'])
      end
      if isscalar(nSigma)
        nSigma=nSigma*ones(1,obj.width);
      elseif numel(nSigma) ~= obj.width
        error([mfilename,': input <nSigma> must have the same number of entries as data width (',...
          num2str(obj.witdh),'), not ',num2str(numel(nSigma)),'.'])
      end
      %create tmp container
      y_data=zeros(obj.length,obj.width);
      if nargout>1; y_outliers=zeros(size(y_data)); end
      %loop over data width, do things quicker if the value of the outliers
      %is not needed.
      if nargout>1
        for i=1:obj.width 
          [y_data(:,i),idx]=simpledata.rm_outliers(obj.y(:,i),'nSigma',nSigma(i),'outlier_value',0);
          y_outliers(idx,i)=obj.y(idx,i);
        end
      else
        for i=1:obj.width
          y_data(:,i)=simpledata.rm_outliers(obj.y(:,i),'nSigma',nSigma(i),'outlier_value',0);
        end
      end
      %sanity
      if nargout>1 && any(any(y_data(obj.mask,:)+y_outliers(obj.mask,:)~=obj.y_masked))
        error([mfilename,':Warning: failed the consistency check: obj.y=y_data+y_outliers. Debug needed!'])
      end
      %propagate (mask is updated inside)
      obj=obj.assign(y_data);
      %optional outputs
      if nargout>1        
        %copy object to preserve metadata
        outliers=obj;
        %propagate gaps
        y_outliers(~obj.mask,:)=NaN;
        %propatate (mask is derived from gaps in y_outliers)
        outliers=outliers.assign(y_outliers,'x',outliers.x,'mask',true(size(outliers.mask)));
        %update descriptor
        outliers.descriptor=['outliers of ',obj.descriptor];
        %do not plot zeros, since they refer to other components, not the
        %component where the outlier was detected
        outliers.plot_zeros=false;
      end
    end
    function obj=medfilt(obj,n)
      %NOTICE: this function does not decimate the data, it simply applies
      %matlab's medfilt function to the data
      obj=obj.assign(medfilt1(obj.y,n)); %,'omitnan','truncate');
    end
    function obj=median(obj,n)
      %create x-domain of medianed data, cutting it into segments of
      %length n, putting each segment in one column of matrix t (x 
      %increases first row-wise, then column-wise)
      %NOTICE: this function decimates the data!
  
      %init matrix that stores the segmented x_temp
      x_temp=nan(n,ceil(obj.length/n));
      x_temp(1:obj.length)=obj.x;
      x_mean=transpose(mean(x_temp,'omitnan'));
      %make room for medianed data
      y_median=nan(ceil(obj.length/n),obj.width);
      %compute media of the data
      s.msg=[mfilename,': computing mean and decimating every ',num2str(n),' data points.'];s.n=obj.width;
      for i=1:obj.width
        %cut the data into segments of length n, putting each segment in
        %one column of matrix y_seg (x increases first row-wise, then 
        %column-wise)
        y_seg=nan(n,ceil(obj.length/n));
        y_seg(1:obj.length)=obj.y(:,i);
        y_median(:,i)=transpose(median(y_seg,'omitnan'));
        %user feedback
        s=time.progress(s,i);
      end
      %sanity
      if numel(x_mean) ~=size(y_median,1)
        error([mfilename,': x-domain length inconsistent with data length, debug needed!'])
      end
      %propagate the x-domain and data
      obj=assign(obj,y_median,'x',x_mean);
      %update descriptor
      obj.descriptor=['median of ',obj.descriptor];
    end
    %% multiple object manipulation
    function out=isxequal(obj1,obj2)
      out=obj1.length==obj2.length && all(obj1.x==obj2.x);
    end
    function compatible(obj1,obj2,varargin)
      %This method checks if the objects are referring to the same
      %type of data, i.e. the data length is not important.
      % parse inputs
      p=inputParser;
      p.KeepUnmatched=true;
      p.addParameter('compatible_parameters',simpledata.compatible_parameter_list,@(i) iscellstr(i))
      % parse it
      p.parse(varargin{:});
      %basic sanity
      if ~strcmp(class(obj1),class(obj2))
        error([mfilename,': incompatible objects: different classes'])
      end
      if (obj1.width ~= obj2.width)
        error([mfilename,': incompatible objects: different number of columns'])
      end
      %shorter names
      par=p.Results.compatible_parameters;
      for i=1:numel(par)
        % if a parameter is empty, no need to check it
        if ( iscell(obj1.(par{i})) && isempty([obj1.(par{i}){:}]) ) || ...
           ( ischar(obj1.(par{i})) && isempty( obj1.(par{i})    ) ) || ...
           ( iscell(obj2.(par{i})) && isempty([obj2.(par{i}){:}]) ) || ...
           ( ischar(obj2.(par{i})) && isempty( obj2.(par{i})    ) )
          continue
        end
        if ~isequal(obj1.(par{i}),obj2.(par{i}))
          error([mfilename,': discrepancy in parameter ',par{i},'.'])
        end 
      end
    end
    function [obj1_out,obj2_out,idx1,idx2]=merge(obj1,obj2,varargin)
      %NOTICE:
      % - idx1 contains the index of the x in obj1 that were added from obj2
      % - idx2 contains the index of the x in obj2 that were added from obj1
      % - no data is propagated between objects, only the time domain is changed!
      %add as gaps in obj2 those x that are in obj1 but not in obj2
      [obj1_out,idx2]=obj1.x_merge(obj2.x);
      if nargout>1
        %add as gaps in obj2 those x that are in obj1 but not in obj2
        [obj2_out,idx1]=obj2.x_merge(obj1.x);
        %sanity on outputs
        if obj1_out.length~=obj2_out.length || any(obj1_out.x~=obj2_out.x)
          error([mfilename,': BUG TRAP: merge operation failed.'])
        end
      end
    end
    function [obj1,obj2]=interp2(obj1,obj2,varargin)
      %extends the x-domain of both objects to be in agreement
      %with the each other. The resulting x-domains possibly have
      %numerous gaps, which are interpolated over (interpolation
      %scheme and other options can be set in varargin).
      compatible(obj1,obj2,varargin{:})
      %trivial call
      if isxequal(obj1,obj2)
        return
      end
      %build extended x-domain
      x_total=simpledata.union(obj1.x,obj2.x);
      %interpolate obj1 over x_total
      obj1=obj1.interp(x_total,varargin{:});
      %interpolate obj2 over x_total
      obj2=obj2.interp(x_total,varargin{:});
    end
    function [obj,idx1,idx2]=append(obj1,obj2)
      %trivial call
      if isempty(obj2)
        idx1=true( obj1.length,1);
        idx2=false(obj1.length,1);
        obj=obj1;
        return
      end
      %sanity
      compatible(obj1,obj2)
      %append with awareness
      if all(obj1.x(end) < obj2.x)
        x_now=[obj1.x;obj2.x];
        y_now=[obj1.y;obj2.y];
        mask_now=[obj1.mask;obj2.mask];
        idx1=[true( obj1.length,1);false(obj2.length,1)];
        idx2=[false(obj1.length,1);true( obj2.length,1)];
      elseif all(obj2.x(end) < obj1.x)
        x_now=[obj2.x;obj1.x];
        y_now=[obj2.y;obj1.y];
        mask_now=[obj2.mask;obj1.mask];
        idx1=[false(obj2.length,1);true( obj1.length,1)];
        idx2=[true( obj2.length,1);false(obj1.length,1)];
      else
        error([mfilename,': cannot append object which are overlaping: ',10,...
          'obj1: ',num2str(obj1.x(1)),' -> ',num2str(obj1.x(end)),10,...
          'obj2: ',num2str(obj2.x(1)),' -> ',num2str(obj2.x(end))])
      end
      %update object
      obj=obj1.assign(y_now,'x',x_now,'mask',mask_now);
    end
    function obj1_out=augment(obj1,obj2,new_data_only)
      %NOTICE:
      % - obj1 receives the data from obj2, at those epochs defined in obj2
      % - data from obj1 with epochs existing in obj2 are discarded (a 
      %   report is given in case there is discrepancy in the data)
      % - the optional argument 'new_data_only' ensures no data from obj1 is
      %   discarded and only new data in obj2 is saved into obj1.
      if ~exist('new_data_only','var') || isempty(new_data_only)
        new_data_only=false;
      end
      %need compatible data
      obj1.compatible(obj2);
      %merge x domain, also get idx2, which is needed to propagate data
      [obj1_out,obj2_out,idx1,idx2]=merge(obj1,obj2);
      %branch on method mode
      if new_data_only
        %find entries with different epochs
        new_idx=find( (idx1~=idx2) & idx2) ;
        %retrieve original data at these entries
        obj2_new=obj2.at(obj2_out.x(new_idx));
        %propagate data
        obj1_out.y(new_idx,:)=obj2_new.y;
        %propagate mask
        obj1_out.mask(new_idx,:)=obj2_new.mask;
      else
        %count data in obj2 which has the same epochs as in obj1 but is different
        common_idx=find(idx1==idx2);
        if any(common_idx) && ( any(obj1_out.mask(common_idx)) ||  any(obj1_out.mask(common_idx)) )
          common_diff_idx=common_idx(any(obj1_out.y(common_idx,:)~=obj2_out.y(common_idx,:),2));
          if ~isempty(common_diff_idx)
            disp(['WARNING:BEGIN',10,'There are ',num2str(numel(common_diff_idx)),...
                ' entries in obj1 that are defined at the same epochs as in obj2 but with different values:'])
            for i=1:min([10,numel(common_diff_idx)])
              disp(str.tablify([16,20,16,12],...
                ['obj1.t(',num2str(common_diff_idx(i)),  ')='],obj1_out.t(common_diff_idx(i)  ),...
                ['obj1.y(',num2str(common_diff_idx(i)),',:)='],obj1_out.y(common_diff_idx(i),:)...
              ))
              disp(str.tablify([16,20,16,12],...
                ['obj2.t(',num2str(common_diff_idx(i)),  ')='],obj2_out.t(common_diff_idx(i)  ),...
                ['obj2.y(',num2str(common_diff_idx(i)),',:)='],obj2_out.y(common_diff_idx(i),:)...
              ))
              disp(str.tablify([16,20,16,12],...
                ['diff.t(',num2str(common_diff_idx(i)),  ')='],obj1_out.t(common_diff_idx(i)  )-obj2_out.t(common_diff_idx(i)  ),...
                ['diff.y(',num2str(common_diff_idx(i)),',:)='],obj1_out.y(common_diff_idx(i),:)-obj2_out.y(common_diff_idx(i),:)...
              ))
            end
            disp(['The data of obj1 have been discarded.',10,'WARNING:END'])
          end
        end
        %propagate data
        obj1_out.y(idx2,:)=obj2.y;
        %propagate mask
        obj1_out.mask(idx2,:)=obj2.mask;
      end
    end
    function out=isequal(obj1,obj2,columns)
      if ~exist('columns','var') || isempty(columns)
        columns=1:obj1.width;
      end
      if any(columns>obj1.width) || any(columns>obj2.width)
        error([mfilename,': requested column indeces exceed width.'])
      end
      %assume objects are not equal
      out=false;
      %check valid data length
      if obj1.nr_valid~=obj2.nr_valid
        return
      end
      %check values themselves
      if any(any(obj1.y_masked([],columns)~=obj2.y_masked([],columns)))
        return
      end
      %they are the same
      out=true;
    end
    %% algebra
    function obj1=plus(obj1,obj2)
      if isnumeric(obj2)
        obj1.y=obj1.y+obj2;
      elseif isnumeric(obj1)
        obj1=obj1+obj2.y;
      else
        %sanity
        compatible(obj1,obj2)
        %operate
        if obj1.length==1
          obj1.y=obj1.y*ones(1,obj2.length)+obj2.y;
        elseif obj2.length==1
          obj1.y=obj2.y*ones(1,obj2.length)+obj1.y;
        else
          %consolidate data sets
          [obj1,obj2]=obj1.merge(obj2);
          %operate
          obj1=obj1.assign(obj1.y+obj2.y,'mask',obj1.mask & obj2.mask);
        end
      end
    end
    function obj1=minus(obj1,obj2)
      if isnumeric(obj2)
        obj1.y=obj1.y-obj2;
      elseif isnumeric(obj1)
        obj1=obj1-obj2.y;
      else
        %sanity
        compatible(obj1,obj2)
        %operate
        if obj1.length==1
          obj1.y=obj1.y*ones(1,obj2.length)-obj2.y;
        elseif obj2.length==1
          obj1.y=obj2.y*ones(1,obj2.length)-obj1.y;
        else
          %consolidate data sets
          [obj1,obj2]=obj1.merge(obj2);
          %operate
          obj1=obj1.assign(obj1.y-obj2.y,'mask',obj1.mask & obj2.mask);
        end
      end
    end
    function obj=scale(obj,scl)
      if isscalar(scl)
        obj.y=scl*obj.y;
      elseif isvector(scl)
        if numel(scl)==obj.width
          for i=1:numel(scl)
            obj.y(:,i)=obj.y(:,i)*scl(i);
          end
        elseif numel(scl)==obj.length
          for i=1:obj.width
            obj.y(:,i)=obj.y(:,i).*scl(:);
          end
        else
          error([mfilename,': if input <scale> is a vector, ',...
            'it must have the same length as either the witdh or length of <obj>.'])
        end
      else
        obj.y=obj.y.*scl;
      end
    end
    function obj=uminus(obj)
      obj=obj.scale(-1);
    end
    function obj=uplus(obj)
      obj=obj.scale(1);
    end
    function obj1=times(obj1,obj2)
      if isnumeric(obj2)
        obj1=obj1.scale(obj2);
      elseif isnumeric(obj1)
        obj1=obj2.scale(obj1).y;
      else
        %sanity
        compatible(obj1,obj2,'compatible_parameters',{'x_units'})
        %operate
        if obj1.length==1
          obj1.y=obj1.y*ones(1,obj2.length).*obj2.y;
        elseif obj2.length==1
          obj1.y=obj2.y*ones(1,obj2.length).*obj1.y;
        else
          %consolidate data sets
          [obj1,obj2]=obj1.merge(obj2);
          %operate
          obj1=obj1.assign(obj1.y.*obj2.y,'mask',obj1.mask & obj2.mask);
        end
      end
    end
    function obj1=rdivide(obj1,obj2)
      if isnumeric(obj2)
        obj1=scale(obj1,1/obj2);
      elseif isnumeric(obj1)
        obj1=obj2.scale(1/obj1).y;
      else
        %sanity
        compatible(obj1,obj2,'compatible_parameters',{'x_units'})
        %operate
        if obj1.length==1
          obj1.y=obj1.y*ones(1,obj2.length)./obj2.y;
        elseif obj2.length==1
          obj1.y=obj2.y*ones(1,obj2.length)./obj1.y;
        else
          %consolidate data sets
          [obj1,obj2]=obj1.merge(obj2);
          %operate
          obj1=obj1.assign(obj1.y./obj2.y,'mask',obj1.mask & obj2.mask);
        end
      end
    end
    function obj=and(obj,obj_new)
      %consolidate data sets
      [obj,obj_new]=obj.merge(obj_new);
      %operate
      obj=obj.mask_and(obj_new.mask);
    end
    function obj=or(obj,obj_new)
      %consolidate data sets
      [obj,obj_new]=obj.merge(obj_new);
      %operate
      obj=obj.mask_or(obj_new.mask);
    end
    function obj=not(obj)
      %build x domain of all explicit gaps
      x_now=obj.x(~obj.mask);
      %build zero data matrix
      y_now=zeros(numel(x_now),obj.width);
      %assign to output
      obj=obj.assign(y_now,'x',x_now);
    end
    %% vector
    function out=norm(obj,p)
      if ~exist('p','var') || isempty(p)
        p=2;
      end
      % computes the p-norm of y
      if p==2
        out=sqrt(sum(obj.y.^2,2));
      elseif p==1
        out=sum(abs(obj.y),2);
      elseif mod(p,2)==0
        out=sum(obj.y.^p,2).^(1/p);
      else
        out=sum(abs(obj.y).^p,2).^(1/p);
      end
    end
    function out=unit(obj)
      % computes the unit vector of y
      out=obj.y./(obj.norm*ones(1,obj.width));
    end
    function obj=dot(obj,obj_new)
      %sanity
      compatible(obj1,obj2,'compatible_parameters',{'x_units'})
      %consolidate data sets
      [obj,obj_new]=obj.merge(obj_new);
      %operate
      obj=obj.assign(sum(obj.y.*obj_new.y,2),'reset_width',true);
    end
    function obj=cross(obj,obj_new)
      %sanity
      compatible(obj1,obj2,'compatible_parameters',{'x_units'})
      %consolidate data sets
      [obj,obj_new]=obj.merge(obj_new);
      %operate
      obj=obj.assign(cross(obj.y,obj_new.y));
    end
    function obj=autocross(obj)
      %get autocross product
      ac=cross(obj.y(1:end-1,:),obj.y(2:end,:));
      %propagate
      obj.y=[...
        ac(1,:);...
        (ac(1:end-1,:)+ac(2:end,:))*5e-1;...
        ac(end,:)...
        ];
    end
    function obj=project(obj,x,y,z)
      %some sanity
      if obj.width~=3
        error([mfilename,': can only project 3D vectors'])
      end
      %no need to consolidate, that is done inside dot
      px=obj.dot(x);
      py=obj.dot(y);
      pz=obj.dot(z);
      %maybe the x-domain needs to be updated
      if obj.length~=px.length || any(obj.x ~=px.x)
        obj.x=px.x;
      end
      %propagate projection
      obj.y=[px.y,py.y,pz.y];
    end
    %% plot methots
    function out=plot(obj,varargin)
      % Parse inputs
      p=inputParser;
      p.KeepUnmatched=true;
      % optional arguments
      p.addParameter('masked',  false,      @(i)islogical(i) && isscalar(i));
      p.addParameter('columns', 1:obj.width,@(i)isnumeric(i) || iscell(i));
      p.addParameter('line'   , {},         @(i)iscell(i));
      p.addParameter('zeromean',false,      @(i)islogical(i) && isscalar(i));
      p.addParameter('outlier', 0,          @(i)isfinite(i) && isscalar(i));
      p.addParameter('title',   '',         @(i)ischar(i));
      % parse it
      p.parse(varargin{:});
      % type conversions
      if iscell(p.Results.columns)
        columns=cell2mat(p.Results.columns);
      else
        columns=p.Results.columns;
      end
      % plot
      y_plot=cell(size(columns));
      for i=1:numel(columns)
        % get data
        y_plot{i}=obj.y(:,columns(i));
        % maybe use a mask
        if p.Results.masked
          out.mask{i}=obj.mask;
        else
          out.mask{i}=true(size(obj.mask));
        end
        % remove outliers if requested
        if p.Results.outlier>1
          for c=1:p.Results.outlier
             [y_plot{i},outlier_idx]=simpledata.rm_outliers(y_plot{i});
             out.mask{i}(outlier_idx)=false;
          end
        end
        % remove mean if requested
        if p.Results.zeromean
          out.y_mean{i}=mean(y_plot{i}(~isnan(y_plot{i})));
        else
          out.y_mean{i}=0;
        end
        % do not plot zeros if defined like that
        if ~obj.plot_zeros
          out.mask{i}=out.mask{i} & ( obj.y(:,columns(i)) ~= 0 );
        end
        % get data
        x_plot=obj.x(out.mask{i});
        y_plot{i}=obj.y(out.mask{i},columns(i))-out.y_mean{i};
        % plot it
        if isempty(p.Results.line)
          out.handle{i}=plot(x_plot,y_plot{i});hold on
        else
          out.handle{i}=plot(x_plot,y_plot{i},p.Results.line{i});hold on
        end
      end
      %set x axis
      if obj.length>1
        xlim([obj.x(1) obj.x(end)])
      end
      %annotate
      if isempty(p.Results.title)
        out.title=obj.descriptor;
      else
        out.title=p.Results.title;
      end
      out.xlabel=['[',obj.x_units,']'];
      if numel(out.handle)==1
        out.ylabel=[obj.labels{columns},' [',obj.y_units{columns},']'];
        if p.Results.zeromean
          out.ylabel=[out.ylabel,' ',num2str(out.y_mean{1})];
        end
        out.legend={};
      else
        same_units=true;
        for i=2:numel(columns)
          if ~strcmp(obj.y_units{columns(1)},obj.y_units{columns(i)})
            same_units=false;
          end
        end
        if same_units
          out.ylabel=['[',obj.y_units{columns(1)},']'];
          out.legend=obj.labels(columns);
        else
          out.ylabel='';
          out.legend=strcat(obj.labels(columns),' [',obj.y_units(columns),']');
        end
        if p.Results.zeromean
          for i=1:numel(columns)
            out.legend{i}=[out.legend{i},' ',num2str(out.y_mean{i})];
          end
        end
      end
      %anotate
      if ~isempty(out.title);   title(str.clean(out.title, 'title')); end
      if ~isempty(out.xlabel); xlabel(str.clean(out.xlabel,'title')); end
      if ~isempty(out.ylabel); ylabel(str.clean(out.ylabel,'title')); end
      if ~isempty(out.legend); legend(str.clean(out.legend,'title')); end
      %outputs
      if nargout == 0
        clear out
      end
    end
    %% convertion methods
    function out=xy(obj)
      %generating matrix
      out=[obj.x,obj.y];
    end
    function out=data(obj,varargin)
      % Parse inputs
      p=inputParser;
      p.KeepUnmatched=true;
      % optional arguments
      p.addParameter('mode',  'xy',              @(i)ischar(i));
      p.addParameter('masked',false,             @(i)islogical(i) && isscalar(i));
      p.addParameter('mask',  true(obj.length,1),@(i)islogical(i) && numel(i)==obj.length);
      % parse it
      p.parse(varargin{:});
      % branching on mode
      switch p.Results.mode
      case 'gaps'
        out=~(obj.mask & p.Results.mask);
      case 'mask'
        out=  obj.mask & p.Results.mask;
      otherwise
        out=obj.(p.Results.mode);
        if p.Results.masked
          out=out(obj.mask & p.Results.mask,:);
        else
          out=out(p.Results.mask,:);
        end
      end
    end
    %% export methods 
    function export(obj,filename,varargin)
      %determine file type
      [~,~,e]=fileparts(filename);
      %branch on extension
      switch e
      case '.mat'
        out=obj.data('masked',true);
        S.x=out(:,1);
        S.y=out(:,2:end);
        S.descriptor=obj.descriptor;
        S.y_units=obj.y_units;
        S.labels=obj.labels;
        S.x_units=obj.x_units; %#ok<STRNU>
        details=whos('S');
        disp(['Saving ',obj.descriptor,' to ',filename,' (',num2str(details.bytes/1024),'Kb).'])
        if nargin>1
          save(filename,'S',varargin{:})
        else
          save(filename,'S','-v7.3')
        end
      otherwise
        error([mfilename,': cannot handle files of type ''',e,'''.'])
      end
    end
    %% import methods
%     function obj=import(filename)
%       %determine file type
%       [p,n,e]=fileparts(filename);
%       %branch on extension
%       switch e
%       otherwise
%         error([mfilename,': cannot handle files of type ''',e,'''.'])
%       end
%     end
  end
end
