module MultiSite::PageControllerExtensions
  def self.included(base)
    base.class_eval {
      before_filter :set_site, :only => [:remove, :new, :edit]
      around_filter :scope_layouts_to_site, :only => [:new, :edit]

      alias_method_chain :index, :root
      %w{edit new remove continue_url clear_model_cache}.each do |m|
        alias_method_chain m.to_sym, :site
      end
    }
  end
  
  def index_with_root
    cookies.delete('expanded_rows')
    if user_developer? # or admin
      if params[:root] # If a root page is specified (should this ever be required for non-developers?)
        @homepage = Page.find(params[:root])
        @site = @homepage.root.site
      elsif (@site = Site.find(:first, :order => "position ASC")) && @site.homepage # If there is a site defined
        @homepage = @site.homepage
      else
        index_without_root
      end
    elsif (@site = current_user.site) && @site.homepage
      @homepage = @site.homepage
    else
      access_denied
    end
    response_for :plural if self.respond_to?(:response_for)
  end

  def remove_with_site
    if user_authorized?
      if request.post?
        announce_pages_removed(@page.children.count + 1)
        @page.destroy
        return_url = session[:came_from]
        session[:came_from] = nil
        if return_url && return_url != admin_pages_path(:root => @page)
          redirect_to return_url
        else
          redirect_to admin_pages_path(:page => @page.parent)
        end
      else
        session[:came_from] = request.env["HTTP_REFERER"]
      end
    else
      access_denied
    end
  end

  def clear_model_cache_with_site
    Page.current_site ||= @site || @page.root.site
    clear_model_cache_without_site
  end

  def new_with_site
    if user_authorized?
      if request.get?
        @page = Page.new_with_defaults(config)
      else
        @page = Page.new
      end

      @page.slug = params[:slug]
      @page.breadcrumb = params[:breadcrumb]
      @page.parent = Page.find_by_id(params[:parent_id] || params[:page_id])
      render :action => :edit unless @page.new_record?
    else
      access_denied
    end
  end

  def edit_with_site
    if user_authorized?
      @old_page_url = @page.url
      return false
    else
      access_denied
    end 
  end

  protected

    def continue_url_with_site(options = {})
      options[:redirect_to] || (params[:continue] ? {:action => 'edit', :id => model.id} : {:action => "index", :root => model.root.id})
    end

    def access_denied
      flash[:error] = 'Access denied.'
      redirect_to login_url
    end

    def user_developer?
      current_user and (current_user.developer? or current_user.admin?)
    end

    def user_authorized?
      user_developer? || (!current_user.nil? && current_user.owner?(@site))
    end

    def set_site
      id = params[:id] || params[:root] || params[:parent_id] || params[:page_id]
      @page = Page.find(id)
      @site = @page.root.site
    end

    def scope_layouts_to_site
      Layout.scoped_to_site(@site.id) do
        yield
      end
    end
end
