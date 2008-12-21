require 'digest/md5'

module LaCoctelera
  
  class InvalidPage < ArgumentError
    def initialize; super end
  end 
  
  class Pagination
    # limit representa cuántos ítems se deben de recuperar cada vez
    # (el nombre viene del LIMIT de SQL)
    attr_reader :page, :per_page, :limit, :params, :global_page, :key_name, :next_key_name, :down_limit, :upper_limit
    
    def initialize(page, per_page, limit, params, extra_identifier = nil)
      @page = page.nil? ? 1 : page.to_i
      @per_page = per_page.to_i
      @limit = limit
      @params = { :action => params['action'] , :controller => params['controller'], :username => params['username']}
      @global_page = (page-1)/(limit/per_page) rescue 0
      @global_page = 0 if @global_page < 0
      @key_name = Digest::MD5.hexdigest("#{@params.to_s}##{extra_identifier}##{@global_page}")
      @next_key_name = Digest::MD5.hexdigest("#{@params.to_s}##{extra_identifier}##{@global_page+1}")
      
      reference_page = (@page%(@limit/@per_page))
      reference_page = (@limit/@per_page) if reference_page == 0

      @down_limit = (reference_page-1)*@per_page
      @upper_limit = (reference_page)*@per_page      
    end
    
    def self.create(page, per_page, limit, params, &block)
      pager = new(page, per_page, limit, params)

      posts = Pagination.get_or_set_from_cache(pager.key_name, 1.minute) do
        yield pager.limit, pager.global_page*pager.limit
      end
      
      # total_entries = pager.calculate_total_entries(posts)
      # Si estamos en el último o penúltimo segmento calculamos el segmento siguiente para detectar 
      # si hay más elementos que paginar o no      
      next_collection = []
      if pager.upper_limit + pager.per_page >= pager.limit
        next_collection = Pagination.get_or_set_from_cache(pager.next_key_name, 1.minute) do
          yield pager.limit, (pager.global_page+1)*pager.limit
        end
      end
      total_entries = next_collection.empty? ? (pager.global_page*pager.limit) + posts.size : (pager.global_page+1)*pager.limit + next_collection.size
      total_entries = posts.size + pager.per_page if total_entries < posts.size
      
      WillPaginate::Collection.create(pager.page, pager.per_page, total_entries) do |will_paginate_pager|
        if posts.size >= pager.upper_limit
          will_paginate_pager.replace(posts[pager.down_limit..pager.upper_limit-1])
        elsif posts.length < pager.upper_limit && posts.length >= pager.down_limit
          will_paginate_pager.replace(posts[pager.down_limit..posts.length-1])
        else
          raise InvalidPage
        end
      end
    end
    
    def self.get_or_set_from_cache(key_name, ttl, &block)
      unless ::Rails.cache.read(key_name)
        result = yield
        begin
          ::Rails.cache.write(key_name, result, :expires_in => ttl) 
        rescue MemCache::MemCacheError
        end
        result
      else
        ::Rails.cache.read(key_name)
      end        
    end
    
  end
    
end