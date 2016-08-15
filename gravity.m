classdef gravity < simpletimeseries
  %static
  properties(Constant)
    %default value of some internal parameters
    default_list=struct(...
      'G',        6.67408e-11,...      % Gravitational constant [m3/kg/s2]
      'GM',       398600.4415e9,...    % Standard gravitational parameter [m^3 s^-2]
      'R',        6378136.460,...      % Earth's equatorial radius [m]
      'Rm',       6371000,...          % Earth's mean radius [m]
      'rho_earth',5514.3231,...        % average density of the Earth = (GM/G) / (4/3*pi*R_av^3) [kg/m3]
      'rho_water',1000,...             % water density
      'love',  [  0       0.000;...    % Love numbers
                  1       0.027;...
                  2      -0.303;...
                  3      -0.194;...
                  4      -0.132;...
                  5      -0.104;...
                  6      -0.089;...
                  7      -0.081;...
                  8      -0.076;...
                  9      -0.072;...
                  10     -0.069;...
                  12     -0.064;...
                  15     -0.058;...
                  20     -0.051;...
                  30     -0.040;...
                  40     -0.033;...
                  50     -0.027;...
                  70     -0.020;...
                  100    -0.014;...
                  150    -0.010;...
                  200    -0.007],...
        'functional','nondim',...
        'source',    'unknown'...
    );
%   Supported functionals are the following,
%       'nondim'    - non-dimensional Stoked coefficients.
%       'eqwh'      - equivalent water height [m]
%       'geoid'     - geoid height [m]
%       'potential' - [m2/s2]
%       'gravity'   - [m /s2], if input represents the disturbing potential,
%                     then the output represents the gravity disturbances.
%                     Otherwise, it represents the gravity accelerations
%                     (-dU/dr).
%       'anomalies' - If input represents the disturbing potential, then
%                     the output represents the gravity anomalies.
%                     Otherwise, it represents (-dU/dr - 2/r*U).
%       'vertgravgrad' - vertical gravity gradient.
    functional_units_list=struct(...
      'nondim',        '[]',...
      'eqwh',          '[m]',...
      'geoid',         '[m]',...
      'potential',     '[m^2.s^{-2}]',...
      'anomalies',     '[m.s^{-2}]',...
      'vertgravgrad',  '[s^{-2}]',...
      'gravity',       '[m.s^{-2}]'...
    );
    parameter_list=struct(...
      'GM',        struct('default',gravity.default_list.GM,        'validation',@(i) isnumeric(i) && isscalar(i)),...
      'R',         struct('default',gravity.default_list.R,         'validation',@(i) isnumeric(i) && isscalar(i)),...
      'functional',struct('default',gravity.default_list.functional,'validation',@(i) ischar(i)),...
      'source',    struct('default',gravity.default_list.source,    'validation',@(i) ischar(i))...
    );

  end
  %read only
  properties(SetAccess=private)
    GM
    R
    functional
    source
  end
  %private (visible only to this object)
  properties(GetAccess=private)
    
  end
  %calculated only when asked for
  properties(Dependent)
    lmax
    mat
    cs
    tri
    mod
  end
  methods(Static)
    function out=parameters
      out=fieldnames(gravity.parameter_list);
    end
    function out=issquare(in)
      in_sqrt=sqrt(in);
      out=(in_sqrt-round(in_sqrt)==0);
    end
    function out=default
      out=gravity.default_list;
    end
    function out=functionals
      out=fieldnames(gravity.functional_units_list);
    end
    function out=functional_units(functional)
      out=gravity.functional_units_list.(functional);
    end
    %% y representation
    function out=y_valid(y)
      out=size(y,1)==1 && gravity.issquare(numel(y));
    end
    function lmax=y_lmax(y)
      lmax=sqrt(numel(y))-1;
    end
    function s=y_length(lmax)
      s=(lmax+1).^2;
    end
    %% mat representation
    function out=mat_valid(mat)
      out=size(mat,1)==size(mat,2);
    end
    function lmax=mat_lmax(mat)
      lmax=y_lmax(mat(:));
    end
    function s=mat_length(lmax)
      s=[lmax+1,lmax+1];
    end
    %% cs representation
    function out=cs_valid(in)
      out=isfield(in,'C') && isfield(in,'S');
      if ~out,return,end
      z=triu(in.C,1)+triu([in.S(:,2:end),zeros(size(in.C,1),1)],0);
      out=all(size(in.C)==size(in.S)) && size(in.C,1) == size(in.C,2) && all(z(:)==0) ;
    end
    function lmax=cs_lmax(cs)
      lmax=gravity.y_lmax(cs.C(:));
    end
    function s=cs_length(lmax)
      s=gravity.mat_length(lmax);
    end
    %% tri representation
    function out=tri_valid(tri)
      lmax=gravity.tri_lmax(tri);
      out=size(tri,1)==lmax+1 && round(lmax)==lmax && gravity.cs_valid(gravity.tri2cs(tri));
    end
    function lmax=tri_lmax(tri)
      lmax=(size(tri,2)+1)/2-1;
    end
    function s=tri_length(lmax)
      s1=gravity.mat_length(lmax);
      s=[s1(1),2*(lmax+1)-1];
    end
    %% mod representation
    function out=mod_valid(mod)
      n=gravity.mod_lmax(mod)+1;
      out=size(mod,2)==4 && size(mod,1)==n*(n+1)/2;
    end
    function lmax=mod_lmax(mod)
      lmax=max(mod(:,1));
    end
    function s=mod_length(lmax)
      s=[(lmax*(lmax+1))/2,2*(lmax+1)-1];
    end
    %% y and mat convertions
    function mat=y2mat(y)
      mat=zeros(sqrt(numel(y)));
      mat(:)=y;
    end
    function y=mat2y(mat)
      y=transpose(mat(:));
    end
    %% cs and mat convertions
    function cs=mat2cs(mat)
      S=transpose(triu(mat,1));
      cs=struct(...
        'C',tril(mat,0),...
        'S',[zeros(size(mat,1),1),S(:,1:end-1)]...
      );
    end
    function mat=cs2mat(cs)
      mat=cs.C+transpose([cs.S(:,2:end),zeros(size(cs.C,1),1)]);
    end
    %% cs and tri convertions
    function tri=cs2tri(cs)
      tri=[fliplr(cs.S(:,2:end)),cs.C];
    end
    function cs=tri2cs(tri)
      n=(size(tri,2)+1)/2;
      cs=struct(...
        'S',[zeros(n,1),fliplr(tri(:,1:n-1))],...
        'C',tri(:,n:end)...
      );
    end
    %% cs and mod convertions
    function mod=cs2mod(in)
      %shortcuts
      n=size(in.C,1);
      %create lower triangle index matrix
      idxm=zeros(n);
      idxm(:)=1:n*n;
      idxm(idxm==triu(idxm,1))=NaN;
      %create index list
      [d,o]=ind2sub(n,idxm(:));
      %get location of NaNs
      i=isnan(d);
      %flatten coefficients
      C=in.C(:);S=in.S(:);
      %filter out upper diagonals
      d(i)=[];
      o(i)=[];
      C(i)=[];
      S(i)=[];
      %assemble
      mod=[d-1,o-1,C,S];
    end
    function out=mod2cs(mod)
      %shortcuts
      n=gravity.mod_lmax(mod)+1;
      %create lower triangle index matrix
      idxm=zeros(n);
      idxm(:)=1:n*n;
      %make room
      out=struct(...
        'C',zeros(max(mod(:,1))+1),...
        'S',zeros(max(mod(:,1))+1)...
      );
      %propagate
      out.C(idxm==tril(idxm, 0)) = mod(:,3);
      out.S(idxm==tril(idxm, 0)) = mod(:,4);
      %assing outputs
    end
    %% agregator routines
    %data type converter
    function out=dtc(from,to,in)
      %trivial call
      if strcmpi(from,to)
        out=in;
        return
      end
      %check input
      if ~gravity.dtv(from,in)
        error([mfilename,': invalid data of type ''',from,'''.'])
      end
      %convert to required types
      switch lower(from)
        case 'y'
          switch lower(to)
            case 'mat'; out=gravity.y2mat(in);
            case 'cs';  out=gravity.mat2cs(gravity.y2mat(in));
            case 'tri'; out=gravity.cs2tri(gravity.mat2cs(gravity.y2mat(in)));
            case 'mod'; out=gravity.cs2mod(gravity.mat2cs(gravity.y2mat(in)));
          end
        case 'mat'
          switch lower(to)
            case 'y';   out=gravity.mat2y(in);
            case 'cs';  out=gravity.mat2cs(in);
            case 'tri'; out=gravity.cs2tri(gravity.mat2cs(in));
            case 'mod'; out=gravity.cs2mod(gravity.mat2cs(in));
          end
        case 'cs'
          switch lower(to)
            case 'y';   out=gravity.mat2y(gravity.cs2mat(in));
            case 'mat'; out=gravity.cs2mat(in);
            case 'tri'; out=gravity.cs2tri(in);
            case 'mod'; out=gravity.cs2mod(in);
          end
        case 'tri'
          switch lower(to)
            case 'y';   out=gravity.mat2y(gravity.cs2mat(gravity.tri2cs(in)));
            case 'mat'; out=gravity.cs2mat(gravity.tri2cs(in));
            case 'cs';  out=gravity.tri2cs(in);
            case 'mod'; out=gravity.cs2mod(gravity.tri2cs(in));
          end
        case 'mod'
          switch lower(to)
            case 'y';   out=gravity.mat2y(gravity.cs2mat(gravity.mod2cs(in)));
            case 'mat'; out=gravity.cs2mat(gravity.mod2cs(in));
            case 'cs';  out=gravity.mod2cs(in);
            case 'tri'; out=gravity.cs2tri(gravity.mod2cs(in));
          end
      end
    end
    %data type validity
    function c=dtv(type,in)
      switch lower(type)
      case 'y';  c=gravity.y_valid(in);
      case 'mat';c=gravity.mat_valid(in);
      case 'cs'; c=gravity.cs_valid(in);
      case 'tri';c=gravity.tri_valid(in);
      case 'mod';c=gravity.mod_valid(in);
      otherwise
        error([mfilename,': unknown data type ''',from,'''.'])
      end
    end
    %data type lmax
    function c=dtlmax(type,in)
      switch lower(type)
      case 'y';  c=gravity.y_lmax(in);
      case 'mat';c=gravity.mat_lmax(in);
      case 'cs'; c=gravity.cs_lmax(in);
      case 'tri';c=gravity.tri_lmax(in);
      case 'mod';c=gravity.mod_lmax(in);
      otherwise
        error([mfilename,': unknown data type ''',from,'''.'])
      end
    end
    %data type length
    function s=dtlength(type,in)
      switch lower(type)
      case 'y';  s=gravity.y_length(in);
      case 'mat';s=gravity.mat_length(in);
      case 'cs'; s=gravity.cs_length(in);
      case 'tri';s=gravity.tri_length(in);
      case 'mod';s=gravity.mod_length(in);
      otherwise
        error([mfilename,': unknown data type ''',from,'''.'])
      end
    end
    %% constructors
    function obj=unit(lmax,scale)
      if ~exist('scale','var') || isempty(scale)
          scale=ones(lmax+1,1);
      end
      %sanity
      if min(size(scale)) ~= 1 || lmax+1 ~= numel(scale)
        error([mfilename,': input ''scale'' has to be a vector with length lmax+1'])
      end
      %create unitary triangular matrix
      t=gravity.dtc('mat','tri',ones(lmax+1));
      %scale along rows
      t=scale(:)*ones(1,size(t,2)).*t;
      %initialize
      obj=gravity(...
        datetime('now'),...
        gravity.dtc('tri','y',t)...
      );
    end
    % creates a unit model with per-degree amplitude equal to 1
    function obj=unit_amplitude(lmax)
      obj=gravity.unit(lmax,1./sqrt(2*(0:lmax)+1));
    end
    % creates a unit model with per-degree RMS equal to 1
    function obj=unit_rms(lmax)
      obj=gravity.unit(lmax,gravity.unit(lmax).drms);
    end
    % Creates a random model with mean 0 and std 1 (per degree)
    function obj=unit_randn(lmax)
      obj=gravity(...
        datetime('now'),...
        gravity.dtc('mat','y',randn(lmax+1))...
      ).scale_nopd;
    end
    function [m,e]=load(filename,type,time)
      %default type
      if ~exist('type','var') || isempty(type)
        type='icgem';
      end
      %default time
      if ~exist('time','var') || isempty(time)
        time=datetime('now');
      end
      switch lower(type)
      case 'gsm'
        [m,e]=load_gsm(filename,time);
      case 'icgem'
        [m,e]=load_icgem(filename,time);
      case 'mod'
        [m,e]=load_mod(filename,time);
      otherwise
        error([mfilename,': cannot handle models of type ''',type,'''.'])
      end
    end
    %general test for the current object
    function out=test_parameters(field,l,w)
      switch field
      case 'something'
        %To be implemented
      otherwise
        out=simpledata.test_parameters(field,l,w);
      end
    end
    function test(l)
      
      m=gravity.load('ggm05g.gfc.txt');
      for i=0:3
        for j=-i:i
          disp(['d=',num2str(i),'; o=',num2str(j),': ',num2str(m.do(i,j))])
        end
      end
      m.plot('das','functional','geoid','showlegend',true)
      return
      
      if ~exist('l','var') || isempty(l)
        l=4;
      end

      nr_coeff=(l+1)^2;
      
      dt={'y','mat','cs','tri','mod'};
      y=randn(1,nr_coeff);
      dd={...
        y,...
        gravity.y2mat(y),...
        gravity.mat2cs(gravity.y2mat(y)),...
        gravity.cs2tri(gravity.mat2cs(gravity.y2mat(y))),...
        gravity.cs2mod(gravity.mat2cs(gravity.y2mat(y)))...
      };
      for i=1:numel(dt)
        for j=1:numel(dt)
          out=gravity.dtc(dt{i},dt{j},dd{i});
          switch dt{j}
          case 'cs'
            c=any(any([out.C,out.S] ~= [dd{j}.C,dd{j}.S]));
          otherwise
            c=any(any(out~=dd{j}));
          end
          if c
            error([mfilename,': failed data type conversion between ''',dt{i},''' and ''',dt{j},'''.'])
          end
        end
      end
      
      disp('--- unit amplitude')
      a=gravity.unit_amplitude(l);
      disp('- C')
      disp(a.cs(1).C)
      disp('- S')
      disp(a.cs(1).S)
      disp('- tri')
      disp(a.tri{1})
      disp('- mod')
      disp(a.mod{1})
      disp('- das')
      disp(a.das)
      
      disp('--- unit rms')
      a=gravity.unit_rms(l);
      disp('- tri')
      disp(a.tri{1})
      disp('- drms')
      disp(a.drms)

      disp('--- change R')
      b=a.change_R(a.R*2);
      disp('- tri')
      disp(b.tri{1})
      
    end
  end
  methods
    %% constructor
    function obj=gravity(t,y,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 't'); %this can be char, double or datetime
      p.addRequired( 'y',     @(i) simpledata.valid_y(i));
      %declare parameters
      for j=1:numel(gravity.parameters)
        %shorter names
        pn=gravity.parameters{j};
        %declare parameters
        p.addParameter(pn,gravity.parameter_list.(pn).default,gravity.parameter_list.(pn).validation)
      end
      % parse it
      p.parse(t,y,varargin{:});
      % call superclass
      obj=obj@simpletimeseries(p.Results.t,p.Results.y,varargin{:},...
        'units',{gravity.functional_units(p.Results.functional)}...
      );
      % save parameters
      for i=1:numel(gravity.parameters)
        %shorter names
        pn=gravity.parameters{i};
        if ~isscalar(p.Results.(pn))
          %vectors are always lines (easier to handle strings)
          obj.(pn)=transpose(p.Results.(pn)(:));
        else
          obj.(pn)=p.Results.(pn);
        end
      end
    end
    function obj=assign(obj,y,varargin)
      %pass it upstream
      obj=assign@simpletimeseries(obj,y,varargin{:});
    end
    function obj=copy_metadata(obj,obj_in)
      %call superclass
      obj=copy_metadata@simpletimeseries(obj,obj_in);
      %propagate parameters of this object
      parameters=gravity.parameters;
      for i=1:numel(parameters)
        if isprop(obj,parameters{i}) && isprop(obj_in,parameters{i})
          obj.(parameters{i})=obj_in.(parameters{i});
        end
      end
    end
    %% lmax
    function obj=set.lmax(obj,l)
      %trivial call
      if obj.lmax==l
        return
      end
      %make room for new matrix representation
      mat_new=cell(obj.length,1);
      %get existing mat representation
      mat_old=obj.mat;
      %branch between extending and truncating
      if obj.lmax<l
        for i=1:obj.length
          %make room for this epoch
          mat_new{i}=zeros(l,l);
          %propagate existing coefficients
          mat_new{i}(1:obj.lmax+1,1:obj.lmax+1)=mat_old{i};
        end
      else 
        for i=1:obj.length
          %truncate
          mat_new{i}=mat_old{i}(1:l+1,1:l+1);
        end
      end
      %assign result
      obj.mat=mat_new;
    end
    function out=get.lmax(obj)
      out=sqrt(obj.width)-1;
    end
    %% representations
    %returns a cell array with matrix representation
    function out=get.mat(obj)
      out=cell(obj.length,1);
      for i=1:obj.length
        out{i}=gravity.dtc('y','mat',obj.y(i,:));
      end
    end
    function obj=set.mat(obj,in)
      %sanity
      if ~iscell(in)
        error([mfilename,': input <in> must be a cell array of matrices.'])
      end
      if (numel(in)~=obj.length)
        error([mfilename,': cannot handle input <in> if it does not have the same number of elements as obj.length.'])
      end
      %make room for data
      y_now=zeros(obj.length,gravity.dtlength('y',gravity.dtlmax('mat',in)));
      %build data 
      for i=1:obj.length
        y_now(i,:)=gravity.mat2y(in{i});
      end
      %assign data
      obj=obj.assign(y_now);
    end
    %returns a structure array with C and S representation
    function out=get.cs(obj)
      out(obj.length)=struct('C',[],'S',[]);
      for i=1:obj.length
        out(i)=gravity.dtc('y','cs',obj.y(i,:));
      end
    end
    function obj=set.cs(obj,in)
      %sanity
      if ~isstruct(in)
        error([mfilename,': input <in> must be a structure array.'])
      end
      if (numel(in)~=obj.length)
        error([mfilename,': cannot handle input <in> if it does not have the same number of elements as obj.length.'])
      end
      %make room for data
      y_now=zeros(obj.length,gravity.dtlength('y',gravity.dtlmax('cs',in)));
      %build data 
      for i=1:obj.length
        y_now(i,:)=gravity.mat2y(gravity.cs2mat(in(i)));
      end
      %assign data
      obj=obj.assign(y_now);
    end
    %return a cell array with triangular matrix representation
    function out=get.tri(obj)
      out=cell(obj.length,1);
      for i=1:obj.length
        out{i}=gravity.dtc('y','tri',obj.y(i,:));
      end
    end
    function obj=set.tri(obj,in)
      %sanity
      if ~isstruct(in)
        error([mfilename,': input <in> must be a cell array of matrices.'])
      end
      if (numel(in)~=obj.length)
        error([mfilename,': cannot handle input <in> if it does not have the same number of elements as obj.length.'])
      end
      %make room for data
      y_now=zeros(obj.length,gravity.dtlength('y',gravity.dtlmax('tri',in)));
      %build data 
      for i=1:obj.length
        y_now(i,:)=gravity.mat2y(gravity.cs2mat(gravity.tri2cs(in)));
      end
      %assign data
      obj=obj.assign(y_now);
    end
    %return a cell array with the mod representation
    function out=get.mod(obj)
      out=cell(obj.length,1);
      for i=1:obj.length
        out{i}=gravity.dtc('y','mod',obj.y(i,:));
      end
    end
    function obj=set.mod(obj,in)
      %sanity
      if ~isstruct(in)
        error([mfilename,': input <in> must be a cell array of matrices.'])
      end
      if (numel(in)~=obj.length)
        error([mfilename,': cannot handle input <in> if it does not have the same number of elements as obj.length.'])
      end
      %make room for data
      y_now=zeros(obj.length,gravity.dtlength('y',gravity.dtlmax('mod',in)));
      %build data 
      for i=1:obj.length
        y_now(i,:)=gravity.mat2y(gravity.cs2mat(gravity.mod2cs(in)));
      end
      %assign data
      obj=obj.assign(y_now);
    end
    %% time handling
    function idx=time2idx(obj,time)
      %find closest time idx
      idx=find(min(abs(seconds(obj.t-time))),1,'first');
    end
    %% coefficient access
    function out=do(obj,d,o,time)
      if ~exist('time','var') || isempty(time)
        time=datetime('now');
      end
      if any(size(d)~=size(o))
        error([mfilename,': inputs ''d'' and ''o'' must have the same size'])
      end
      %get indexes of the C-coefficients
      C_idx=o>=0;
      %make room for output
      out=zeros(size(d));
      %retrive cosine coefficients
      out(C_idx)=obj.mat{obj.time2idx(time)}(d(C_idx)+1,o(C_idx)+1);
      %retrieve sine coefficients
      out(~C_idx)=obj.mat{obj.time2idx(time)}(-o(~C_idx),d(~C_idx)+1);
    end
    %% scaling functions
    % radius scaling
    function s=scale_radius(obj,r)
      s=(obj.R/r).^(0:obj.lmax);
    end
    % functional scaling
    function s=scale_functional(obj,functional_new)
      %   Supported functionals are the following,
      %       'non-dim'   - non-dimensional Stoked coefficients.
      %       'eqwh'      - equivalent water height [m]
      %       'geoid'     - geoid height [m]
      %       'potential' - [m2/s2]
      %       'gravity'   - [m /s2], if input represents the disturbing potential,
      %                     then the output represents the gravity disturbances.
      %                     Otherwise, it represents the gravity accelerations
      %                     (-dU/dr).
      %       'anomalies' - If input represents the disturbing potential, then
      %                     the output represents the gravity anomalies.
      %                     Otherwise, it represents (-dU/dr - 2/r*U).
      %       'vert-grav-grad' - vertical gravity gradient.
      %get nr of degrees
      N=obj.lmax+1;
      %get pre-scaling      
      switch lower(obj.functional)
        case 'nondim'
          %no scaling
          pre_scale=ones(N);
        otherwise
          %need to bring these coefficients down to 'non-dim' scale
          pre_scale = mod_convert_aux('nondim',from,N,obj.GM,obj.R);
      end
      %get pos-scaling
      switch lower(functional_new)
        case 'nondim'
          %no scaling
          pos_scale=ones(N);
        case 'eqwh' %[m]
          pos_scale=zeros(N);
          %converting Stokes coefficients from non-dimensional to equivalent water layer thickness
          for i=1:N
            deg=i-1;
            lv=interp1(...
              gravity.default_list.love(:,1),...
              gravity.default_list.love(:,2),...
              deg,'linear','extrap');
            pos_scale(i,:)=obj.R*(rho_earth/rho_water) * 1/3 * (2*deg+1)/(1+lv);
          end
        case 'geoid' %[m]
          pos_scale=ones(N)*obj.R;
        case 'potential' %[m2/s2]
          pos_scale=ones(N)*obj.GM/obj.R;
        case 'gravity' %[m/s2]
          %If input represents the disturbing potential, then the output
          %represents the gravity disturbances. Otherwise, it represents the
          %gravity accelerations (-dU/dr).
          deg=(0:N-1)'*ones(1,N);
          pos_scale=-obj.GM/obj.R^2*(deg+1);
        case 'anomalies'
          %If input represents the disturbing potential, then the output
          %represents the gravity anomalies. Otherwise, it represents:
          %-dU/dr - 2/r*U
          deg=(0:N-1)'*ones(1,N);
          pos_scale=obj.GM/obj.R^2*max(deg-1,ones(size(deg)));
        case 'vertgravgrad'
          deg=(0:N-1)'*ones(1,N);
          pos_scale=obj.GM/obj.R^3*(deg+1).*(deg+2);
        otherwise
          error([mfilename,': unknown scale ',functional_new])
      end
      %outputs
      s=pos_scale./pre_scale;
    end
    % Gaussan smoothing scaling
    function s=scale_gauss(obj,radius)
      b=log(2)/(1-cos(radius/obj.default_list.R));
      c=exp(-2*b);
      s=zeros(1,obj.lmax+1);
      s(1)=1d0;                       %degree 0
      s(2)=s(1)*((1+c)/(1-c) - 1/b);	%degree 1
      for l=2:obj.lmax
        s(l+1)=-(2*l+1)/b*s(l)+s(l-1);
        if (abs(s(l+1)) > abs(s(l)))
          s(l+1) = 0d0;
        end
      end
    end
    % scale according to number of orders in each degree
    function s=scale_nopd(obj)
      s=1./obj.nopd;
    end
    % scale operation agregator
    function obj=scale(obj,s,method)
      if ~exist('method','var') || isempty(method)
        switch numel(s)
        case obj.lmax+1
          %per-degree scaling
          tri_now=obj.tri;
          scale_mat=s(:)*ones(size(tri_now,2),1);
          for i=1:obj.length
            tri_now{i}=tri_now.*scale_mat;
          end
          obj.tri=tri_now;
        case {1,obj.width}
          %global or per-coefficients scaling: call mother routine 
          obj=scale@simpledata(obj,s);
        otherwise
          error([mfilename,': cannot handle scaling factors with number of elements equal to ',...
            num2str(numel(s)),'; either max degree+1 (',num2str(obj.lmax+1),') or nr of coeffs (',...
            num2str(obj.width),').'])
        end
      else
        % input 's' assumes different meanings, dependending on the method
        obj=obj.scale(obj.(['scale_',method])(s));
        %need to update metadata in some cases
        switch lower(method)
          case 'radius'
            obj.R=s;
          case 'functional'
            obj.functional=s;
            obj.y_units=gravity.functional_units(s);
        end
      end
    end
    %% derived quantities
    % number of orders in each degree
    function out=nopd(obj)
      out=2*(1:obj.lmax+1)-1;
    end
    %degree mean
    function out=dmean(obj)
      out=zeros(obj.length,obj.lmax+1);
      tri_now=obj.tri;
      for i=1:obj.length
        %compute mean over each degre
        out(i,:) = mean(tri_now{i},2);
      end
    end
    %cumulative degree mean
    function out=cumdmean(obj)
      out=cumsum(obj.dmean,2);
    end
    %degree RMS
    function out=drms(obj)
      das=obj.das;
      out=zeros(size(das));
      l=obj.nopd;
      for i=1:obj.length
        out(i,:)=das(i,:)./sqrt(l);
      end
    end
    %cumulative degree RMS
    function out=cumdrms(obj)
      out=sqrt(cumsum(obj.drms.^2,2));
    end
    %degree STD
    function out=dstd(obj)
      out=sqrt(obj.drms.^2-obj.dmean.^2);
    end
    %cumulative degree mSTD
    function out=cumdstd(obj)
      out=cumsum(obj.dstd,2);
    end
    % returns degree amplitude spectrum for each row of obj.y. The output
    % matrix has in each row the epochs of obj.y (corresponding to the epochs
    % of the models) and for each column i the degree i-1 (this is implicit).
    function out=das(obj)
      out=zeros(obj.length,obj.lmax+1);
      tri_now=obj.tri;
      for i=1:obj.length
        %compute DAS
        out(i,:) = sqrt(sum(tri_now{i}.^2,2));
      end
    end
    % returns the cumulative degree amplitude spectrum for each row of obj.y.
    % the output matrix is arranged as <das>.
    function out=cumdas(obj)
      out=cumsum(obj.das,2);
    end
    %% plot functions
    function axishandle=plot(obj,method,varargin)
      % Parse inputs
      p=inputParser;
      p.KeepUnmatched=true;
      % optional arguments
      p.addParameter('showlegend',false,@(i)islogical(i));
      p.addParameter('functional',obj.functional,gravity.parameter_list.functional.validation);
      % parse it
      p.parse(varargin{:});
      % enforce requested functional
      if ~strcmpi(obj.functional,p.Results.functional)
        obj=obj.scale(p.Results.functional,'functional');
      end
      % branch on method
      switch lower(method)
      case {'dmean','cumdmean','drms','cumdrms','dstd','cumdstd','das','cumdas'}
        v=transpose(obj.(method));
        axishandle=semilogy(transpose(v));
        hold on
        title(simpledata.strclean(obj.descriptor))
        xlabel('SH degree')
        ylabel([obj.functional,' ',obj.y_units])
        if p.Results.showlegend
          legend(datestr(obj.t))
        end
      otherwise
        error([mfilename,': unknonw method ''',method,'''.'])
      end
      
    end
  end
end

%% load interfaces
function [m,e]=load_gsm(filename,time)
  %open file
  fid=fopen(filename);
  modelname=''; GM=0; radius=0; Lmax=0; %Mmax=0;
  % Read header
  s=fgets(fid);
  while(strncmp(s, 'GRCOF2', 6) == 0)
     if (keyword_search(s, 'FIRST'))
       modelname =strtrim(s(7:end)); 
     end
     if (keyword_search(s, 'EARTH'))
       x=str2num(s(7:end));
       GM=x(1);
       radius=x(2);
     end
     if keyword_search(s, 'SHM') && ~keyword_search(s, 'SHM*')
       x=str2num(s(4:16));
       Lmax=x(1);
       %Mmax=x(2);
       permanent_tide=strfind(s,'inclusive permanent tide');
     end
     s=fgets(fid);
  end
  %sanity
  if sum(s)<0
     error([mfilename,': Problem with reading the GRCOF2 file ''',filename,'''.'])
  end
  %make room for coefficients
  mi.C=zeros(Lmax+1);
  mi.S=zeros(Lmax+1);
  ei.C=zeros(Lmax+1);
  ei.S=zeros(Lmax+1);
  % read coefficients
  while (s>=0)
    %skip empty lines
    if numel(s)<5
      s=fgets(fid);
      continue
    end
    %get numeric data
    x=str2num(s(7:76)); %#ok<*ST2NM>
    %save degree and order
    n=x(1)+1;
    mi=x(2)+1;
    %check if this is a valid line
    if strcmp(s(1:6),'GRCOF2')
      mi.C(n,mi)=x(3);
      mi.S(n,mi)=x(4);
      if (numel(x)>=6),
         ei.C(n,mi)=x(5);
         ei.S(n,mi)=x(6);
      end
    else
      error([mfilename,': unexpected tag in line: ''',s,''.'])
    end
    % read next line
    s=fgets(fid);
  end
  %fix permanent_tide
  if permanent_tide
    mi.C(3,1)=mi.C(3,1)-4.173e-9;
  end
  %initializing data object
  m=gravity(...
    time,...
    gravity.dtc('cs','y',mi),...
    'GM',GM,...
    'R',radius,...
    'descriptor',modelname,...
    'source',filename...
  );
  if any(ei.C(:)~=0) || any(ei.S(:)~=0)
    %initializing error object
    e=gravity(...
      time,...
      gravity.dtc('cs','y',ei),...
      'GM',GM,...
      'R',radius,...
      'descriptor',['error of ',modelname],...
      'source',filename...
    );
  end
end
function [m,e,trnd,acos,asin]=load_icgem(filename,time)
%This function is an adaptation of icgem2mat.m from rotating_3d_globe, by
%Ales Bezdek, which can be found at:
%
%http://www.asu.cas.cz/~bezdek/vyzkum/rotating_3d_globe/
%
%The original header is transcribed below.
%
%J.Encarnacao (j.g.deteixeiradaencarnacao@tudelft.nl) 11/2013
%
% ICGEM2MAT   Reads geopotential coefficients from an ICGEM file and saves them in a mat file.
%
% Usage:
%
%       icgem2mat
%
% finds all the ICGEM files (*.gfc) in the current directory,
% reads the geopotential coefficients, transforms them into Matlab variables:
%       header...structure with Icgem header information
%       mi.C(n+1,m+1), mi.S(n+1,m+1)...harmonic coefficients C(n,m), S(n,m)
%
% The new mat file with the same name is moved into 'data_icgem' subdirectory;
% the original gfc file is moved into 'data_icgem/gfc/' subdirectory.
%
% Add the 'data_icgem' folder into your Matlab path.
% The model coefficients are then loaded by typing, e.g.:
%
%          load egm2008
%
% To display the C(2,0) zonal term type
%
%          mi.C(3,1)
%
%
% See also compute_geopot_grids
%
% Ales Bezdek, bezdek@asu.cas.cz, 11/2012
%
% clear
% NMAX=360;
% NMAX=1e100;  %it is possible to limit the maximum degree read from the gfc file
% adr_data='./';
% adr_kam='./data_icgem/';
%
% seznam_soub=dir(adr_data);
% soub={seznam_soub.name};   %cell with filenames
% for i=1:length(soub)
%    jm=soub{i};
%    if length(jm)>4 && strcmpi(jm(end-3:end),'.gfc')
%       soub1=jm(1:end-4);
%       fprintf('Gfc file processed: %s\n',soub1);
%       filename=[adr_data soub1 '.gfc'];

  %default time
  if ~exist('time','var') || isempty(time)
    time=datetime('now');
  end
  %open file
  fid=fopen(filename);
  % init header
  header=struct(...
      'product_type',           '',...
      'modelname',              '',...
      'model_content',          '',...
      'earth_gravity_constant', [],...
      'radius',                 [],...
      'max_degree',             [],...
      'errors',                 '',...
      'norm',                   '',...
      'tide_system',            '',...
      'filename',               filename...
  );
  % Read header
  s=fgets(fid);
  fn=fieldnames(header);
  while(strncmp(s, 'end_of_head', 11) == 0 && sum(s)>=0)
    for j=1:numel(fn)
      f=fn{j};
      if (keyword_search(s,f))
        valuestr=strtrim(s(length(f)+1:end));
        switch class(header.(f))
          case 'double'
            header.(f)=str2double(strrep(valuestr,'D','e'));
          case 'char'
            header.(f)=valuestr;
          otherwise
          error([mfilename,': cannot handle class ',class(header.(f)),'.'])
        end
      end
    end
    s=fgets(fid);
  end
  if s<0
    error([mfilename,'Problem reading the gfc file.'])
  end
  % sanity on max degree
  if isempty(header.max_degree)
    error([mfilename,': could not determine maximum degree of model ''',filename,'''.'])
  end
  % make room for coefficients
  mi=struct('C',zeros(header.max_degree+1),'S',zeros(header.max_degree+1),'t0',[]);
  ei=struct('C',zeros(header.max_degree+1),'S',zeros(header.max_degree+1));
  trnd=struct('C',[],'S',[]);
  acos=struct('C',[],'S',[]);
  asin=struct('C',[],'S',[]);
  %iterators
  i_t0=0;
  i_trnd=0; %pocet clenu s trendem
  i_acos=0; %pocet clenu
  i_asin=0; %pocet clenu
  i_gfc=0;
  %read data
  s=fgets(fid);
  while (s>=0)
    %skip empty lines
    if numel(s)<5
      s=fgets(fid);
      continue
    end
    %retrieve keywords, degree and order
    x=str2num(s(5:end));
    n=x(1)+1;
    m=x(2)+1;
    if strcmp(s(1:4),'gfct')
      i_t0=i_t0+1;
      mi.C(n,m)=x(3);
      mi.S(n,m)=x(4);
      [yr,mn,dy]=ymd2cal(x(end)/1e4);
      yrd=jd2yr(cal2jd(yr,mn,dy));
      if isempty(mi.t0)
        mi.t0=zeros(grep_nr_occurences(filename,'gfct'));
        if numel(mi.t0)==0; error([mfilename,'Problem with gfct']); end
      end
      mi.t0(i_t0,:)=[n m yrd]; 
      if (strcmp(header.errors,'formal') || ...
          strcmp(header.errors,'calibrated') || ...
          strcmp(header.errors,'calibrated_and_formal'))
        ei.C(n,m)=x(5);
        ei.C(n,m)=x(6);
      end
    elseif strcmp(s(1:3),'gfc')
      mi.C(n,m)=x(3);
      mi.S(n,m)=x(4);
      if (strcmp(header.errors,'formal') || ...
          strcmp(header.errors,'calibrated') || ...
          strcmp(header.errors,'calibrated_and_formal'))
        ei.C(n,m)=x(5);
        ei.C(n,m)=x(6);
      end
      i_gfc=i_gfc+1;
    elseif strcmp(s(1:4),'trnd') || strcmp(s(1:3),'dot')
      if isempty(trnd.C)
        trnd.C=zeros(grep_nr_occurences(filename,'trnd')+grep_nr_occurences(filename,'dot'),3); trnd.S=trnd.C;
        if numel(trnd.C)==0; error([mfilename,'Problem with trnd']); end
      end
      i_trnd=i_trnd+1;
      trnd.C(i_trnd,:)=[n m x(3)]; 
      trnd.S(i_trnd,:)=[n m x(4)]; 
    elseif strcmp(s(1:4),'acos')
      if isempty(acos.C)
        acos.C=zeros(grep_nr_occurences(filename,'acos'),4); acos.S=acos.C;
        if numel(asin.C)==0; error([mfilename,'Problem with acos']); end
      end
      i_acos=i_acos+1;
      acos.C(i_acos,:)=[n m x(3) x(end)];
      acos.S(i_acos,:)=[n m x(4) x(end)];
    elseif strcmp(s(1:4),'asin')
      if isempty(asin.C)
        asin.C=zeros(grep_nr_occurences(filename,'asin'),4); asin.S=asin.C;
        if numel(asin.C)==0; error([mfilename,'Problem with asin']); end
      end
      i_asin=i_asin+1;
      asin.C(i_asin,:)=[n m x(3) x(end)];
      asin.S(i_asin,:)=[n m x(4) x(end)];
    else
      error([mfilename,'A problem occured in gfc data.']);
    end
    s=fgets(fid);
  end
  fclose(fid);
  %handle the tide system
  switch header.tide_system
    case 'zero_tide'
      %do nothing, this is the default
    case {'free_tide','tide_free'}
      mi.C(3,1)=mi.C(3,1)-4.173e-9;
      header.tide_system='zero_tide';
    case 'mean_tide'
      %http://mitgcm.org/~mlosch/geoidcookbook/node9.html
      mi.C(3,1)=mi.C(3,1)+1.39e-8;
      header.tide_system='zero_tide';
    otherwise
      %the tide system is not documented, so make some assumptions
      switch header.modelname
        case 'GROOPS'
          %do nothing, Norber Zehentner's solutions are zero tide
        otherwise
          error([mfilename,': unknown tide system ''',header.tide_system,'''.'])
      end
  end
  %initializing data object
  m=gravity(...
    time,...
    gravity.dtc('cs','y',mi),...
    'GM',header.earth_gravity_constant,...
    'R',header.radius,...
    'descriptor',header.modelname,...
    'source',header.filename...
  );
  if any(ei.C(:)~=0) || any(ei.S(:)~=0)
    %initializing error object
    e=gravity(...
      time,...
      gravity.dtc('cs','y',ei),...
      'GM',header.earth_gravity_constant,...
      'R',header.radius,...
      'descriptor',['error of ',header.modelname],...
      'source',header.filename...
    );
  end
end
function [m,e]=load_mod(filename,time)
  %loading data
  [mi,headerstr]=textscanh(filename);
  %init constants
  header=struct(...
    'GM',gravity.default_list.GM,...
    'R',gravity.default_list.R,...
    'name','unknown'...
  );
  %going through all header lines
  for i=1:numel(headerstr)
    %checking if this is one of the ID strings
    for j=1:fieldnames(header)
      fieldname=j{1};
      if keyword_search(headerstr{i},[fieldname,':'])
        valuestr=strrep(headerstr{i},[fieldname,':'],'');
        switch class(header.(fieldname))
        case 'double'
          header.(fieldname)=str2double(valuestr);
        case 'char'
          header.(fieldname)=valuestr;
        otherwise
          error([mfilename,': cannot handle class ',class(header.(fieldname)),'.'])
        end
      end
    end
  end
  %initializing data object
  m=gravity(...
    time,...
    gravity.dtc('mod','y',mi),...
    'GM',header.GM,...
    'R',header.R,...
    'descriptor',header.name,...
    'source',filename...
  );
  %no error info on mod format
  e=[];
end

%% Aux functions
function out=keyword_search(line,keyword)
    out=strncmp(line,       keyword,         length(keyword)) || ...
        strncmp(line,strrep(keyword,' ','_'),length(keyword));
end
function out=grep_nr_occurences(filename,pattern)
   [~, result] =system(['grep -c ',pattern,' ',filename]);
   out=str2double(result);
end
function [data,header] = textscanh(filename)
  %sanity
  if isempty(filename)
      error([mfilename,': cannot handle empty filenames.'])
  end
  %open file
  fid = fopen_disp(filename,[],true);
  %maximum number of lines to scan for header
  max_header_len = 50;
  %init header
  header_flag = zeros(max_header_len,1);
  header=cell(size(header_flag));
  %determining number of header lines
  for i=1:max_header_len
    header{i} = fgetl(fid);
    header_flag(i) = isnumstr(header{i});
  end
  %checking for number of header lines > max_header_len
  if ~isnumstr(fgetl(fid))
      error([mfilename,': file ',fopen(fid),' has more header lines than max search value (',num2str(max_header_len),').']);
  end
  %counting number of header lines and cropping
  if isempty(header)
    header_lines = 0;
    header=[];
  else
    header_lines = find(diff(header_flag)==1,1,'last');
    if ~isempty(header_lines)
      header=header(1:header_lines);
    else
      header_lines=0;
    end
  end
  %disp([mfilename,':debug: header contains ',num2str(header_lines),' lines.'])
  frewind(fid);
  %try to read one byte
  if fseek(fid,1,'bof') ~= 0
    error([mfilename,': file ',fopen(fid),' is empty.'])
  end
  frewind(fid);
  %load the data
  data  = textscan(fid,'',nlines,'headerlines',header_lines,...
                     'returnonerror',0,'emptyvalue',0);
  %close the file
  fclose(fid);
  %need to be sure that all columns have equal length
  min_len = 1/eps;
  for i=1:length(data)
    min_len = min(size(data{i},1),min_len);
  end
  %cropping so that is true
  for i=1:length(data)
    data{i} = data{i}(1:min_len,:);
  end
  %numerical output, so transforming into numerical array
  data=[data{:}];
end
function out = isnumstr(in)
  %Determines if the input string holds only numerical data. The test that is
  %made assumes that numerical data includes only the characters defined in
  %<num_chars>.
  if isnumeric(in)
      out=true;
      return
  end
  %characters that are allowed in numerical strings
  num_chars = ['1234567890.-+EeDd:',9,10,13,32];
  %deleting the numerical chars from <in>
  for i=1:length(num_chars)
      num_idx = strfind(in,num_chars(i));
      if ~isempty(num_idx)
          %flaging this character
          in(num_idx)='';
      end
  end
  %now <in> must be empty (if only numerical data)
  out = isempty(in);
end
